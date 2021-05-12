#!/usr/bin/env bash
set -Eeuo pipefail

shell="$(
	wget -qO- 'https://downloads.mongodb.org/current.json' \
	| jq -r '
		[
			.versions[]

			# filter out download objects we are definitely not interested in (enterprise, rhel, etc)
			| del(.downloads[] | select(
				(
					.edition == "base"
					or .edition == "targeted"
				)
				and (
					.target // ""
					| (
						test("^(" + ([
							"debian[0-9]+", # debian10, debian11, etc
							"ubuntu[0-9]{4}", # ubuntu2004, ubuntu1804, etc
							"windows.*" # windows, windows_x86_64, windows_x86_64-2012plus, etc
						] | join("|")) + ")$")
						and (
							# a few things old enough we do not want anything to do with them /o\
							test("^(" + ([
								"debian[89].*",
								"ubuntu14.*"
							] | join("|")) + ")$")
							| not
						)
					)
				)
			| not))

			| {
				version: (
					# convert "4.4.x" into "4.4" and "4.9.x-rcY" into "4.9-rc"
					(.version | split(".")[0:2] | join("."))
					+ if .release_candidate then "-rc" else "" end
				),
				meta: .,
			}

			# filter out EOL versions
			# (for some reason "current.json" still lists all these, and as of 2021-05-13 there is not an included way to differentiate them)
			| select(.version as $v | [
				# https://www.mongodb.com/support-policy -> "MongoDB Server" -> "End of Life Date"
				"3.0", # February 2018
				"3.2", # September 2018
				"3.4", # January 2020
				"3.6", # April 2021
				null # ... so we can have a trailing comma above, making diffs nicer :trollface:
			] | index($v) | not)
		]

		# now convert all that data to a basic shell list + map so we can loop over/use it appropriately
		| "allVersions=( " + (map(.version | @sh) | join(" ")) + " )\n"
		+ "declare -A versionMeta=(\n" + (
			map(
				"\t[" + (.version | @sh) + "]="
				+ (.meta | @json | @sh)
			) | join("\n")
		) + "\n)"
	'
)"
eval "$shell"

versions=( "$@" )
if [ ${#versions[@]} -eq 0 ]; then
	versions=( "${allVersions[@]}" )
	json='{}'
else
	versions=( "${versions[@]%/}" )
	json="$(< versions.json)"
fi

for version in "${versions[@]}"; do
	export version
	_jq() { jq <<<"${versionMeta[$version]}" "$@"; }

	#echo "$version: $fullVersion"
	_jq -r 'env.version + ": " + .version'

	# download the Windows MSI sha256 (so we can embed it)
	msiUrl="$(_jq -r '.downloads[] | select(.target | test("^windows")) | .msi // ""')"
	[ -n "$msiUrl" ]
	[[ "$msiUrl" != *$'\n'* ]] # just in case they do something wild like support windows-arm64 :D
	# 4.3 doesn't seem to have a sha256 file (403 forbidden), so this has to be optional :(
	msiSha256="$(wget -qO- "$msiUrl.sha256" || :)"
	msiSha256="${msiSha256%% *}"
	export msiUrl msiSha256

	# GPG keys
	if [[ "$version" == *-rc ]]; then
		# the "testing" repository (used for RCs) could be signed by any of the GPG keys used by the project
		gpgKeys="$(grep -E '^[0-9.]+:' gpg-keys.txt | cut -d: -f2 | xargs)"
	else
		gpgKeyVersion="$version"
		minor="${version#*.}" # "4.3" -> "3"
		if [ "$(( minor % 2 ))" = 1 ]; then
			gpgKeyVersion="${version%.*}.$(( minor + 1 ))"
		fi
		gpgKeys="$(grep "^$gpgKeyVersion:" gpg-keys.txt | cut -d: -f2)"
	fi
	[ -n "$gpgKeys" ]
	export gpgKeys

	json="$(
		{
			jq <<<"$json" -c .
			_jq '{ (env.version): (
				with_entries(select(.key as $key | [
					# interesting bits of raw upstream metadata
					"changes",
					"date",
					"githash",
					"notes",
					"version",
					null # ... trailing comma hack
				] | index($key)))
				+ {
					gpg: (env.gpgKeys | split(" ") | sort),
					targets: (
						reduce (
							.downloads[]
							| .target |= sub("^windows.*$"; "windows")
						) as $d ({}; $d.target as $t |
							.[$t].arches |= (. + [
								{
									# mapping from "current.json" arch values to bashbrew arch values
									"aarch64": "arm64v8",
									"arm64": "arm64v8",
									"s390x": "s390x",
									"x86_64": "amd64",
								}[$d.arch] // ("unknown:" + $d.arch)
							] | sort)
							| if $t | test("^(debian|ubuntu)") then
								.[$t].image = (
									{
										"debian10": "debian:buster-slim",
										"debian11": "debian:bullseye-slim",
										"ubuntu1604": "ubuntu:xenial",
										"ubuntu1804": "ubuntu:bionic",
										"ubuntu2004": "ubuntu:focal",
									}[$t] // "unknown"
								)
								| .[$t].suite = (
									.[$t].image
									| gsub("^.*:|-slim$"; "")
								)
							else . end
						)
					),
				}
				| .targets.windows += {
					msi: env.msiUrl,
					sha256: env.msiSha256,
					variants: [
						"windowsservercore-1809",
						"windowsservercore-ltsc2016",
						"nanoserver-1809"
					],
					features: ([
						# https://github.com/mongodb/mongo/blob/r4.4.2/src/mongo/installer/msi/wxs/FeatureFragment.wxs#L9-L92 (no MonitoringTools,ImportExportTools)
						# https://github.com/mongodb/mongo/blob/r4.2.11/src/mongo/installer/msi/wxs/FeatureFragment.wxs#L9-L116
						# https://github.com/mongodb/mongo/blob/r4.0.21/src/mongo/installer/msi/wxs/FeatureFragment.wxs#L9-L128
						"ServerNoService",
						"Client",
						"Router",
						"MiscellaneousTools",
						if [ "4.2", "4.0" ] | index(env.version) then
							"ImportExportTools",
							"MonitoringTools"
						else empty end
					] | sort),
				}
				# ignore anything that does not support amd64
				| del(.targets[] | select(.arches | index("amd64") | not))
				| .linux = (
					# automatically choose an appropriate linux target, preferring (in order):
					# - more supported architectures
					# - debian over ubuntu
					# - newer release over older
					.targets
					| to_entries
					| [ .[] | select(.key | test("^(debian|ubuntu)")) ]
					| sort_by([
						(.value.arches | length),
						(
							.key
							| if startswith("ubuntu") then
								1
							elif startswith("debian") then
								2
							else 0 end
						),
						(.key | sub("^(debian|ubuntu)"; "") | tonumber), # 10, 11, 2004, 1804, etc
						.key
					])
					| reverse[0].key
				)
				| .
			) }'
		} | jq -cs add
	)"
done

jq <<<"$json" -S . > versions.json

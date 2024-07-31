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
								"ubuntu1[0-9].*"
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
				# https://www.mongodb.com/support-policy/lifecycles
				"3.0", # February 2018
				"3.2", # September 2018
				"3.4", # January 2020
				"3.6", # April 2021
				"4.0", # April 2022
				"4.2", # April 2023
				null # ... so we can have a trailing comma above, making diffs nicer :trollface:
			] | index($v) | not)

			# filter out so-called "rapid releases": https://docs.mongodb.com/upcoming/reference/versioning/
			# "Rapid Releases are designed for use with MongoDB Atlas, and are not generally supported for use in an on-premise capacity."
			| select(
				(.version | split("[.-]"; "")) as $splitVersion
				| ($splitVersion[0] | tonumber) >= 5 and ($splitVersion[1] | tonumber) > 0
				| not
			)
		]

		# now convert all that data to a basic shell list + map so we can loop over/use it appropriately
		| "allVersions=( " + (
			map(.version | ., if endswith("-rc") then empty else . + "-rc" end)
			| unique
			| map(@sh)
			| join(" ")
		) + " )\n"
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

	if [ -z "${versionMeta[$version]:+foo}" ]; then
		echo >&2 "warning: skipping/removing '$version' (does not appear to exist upstream)"
		json="$(jq <<<"$json" -c '.[env.version] = null')"
		continue
	fi
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

	export pgpKeyVersion="${version%-rc}"
	pgp='[]'
	if [ "$pgpKeyVersion" != "$version" ]; then
		# the "testing" repository (used for RCs) has a dedicated PGP key (but still needs the "release" key for the release line)
		pgp="$(jq -c --argjson pgp "$pgp" '$pgp + [ .dev // error("missing PGP key for dev") ]' pgp-keys.json)"

		# if {{ env.rcVersion }} is not GA, so we need the previous release for mongodb-mongosh and mongodb-database-tools
		isDotZeroPrerelease="$(_jq -r '.version | ltrimstr(env.pgpKeyVersion) | startswith(".0-")')"
		if [ "$isDotZeroPrerelease" = 'true' ]; then
			pgp="$(
				jq -c --argjson pgp "$pgp" '
					(env.pgpKeyVersion | split(".") | .[0] |= (tonumber - 1 | tostring) | join(".")) as $previousVersion
					| $pgp + [ .[$previousVersion] // error("missing PGP key for \($previousVersion)") ]
				' pgp-keys.json
			)"
		fi
	fi
	minor="${pgpKeyVersion#*.}" # "4.3" -> "3"
	if [ "$(( minor % 2 ))" = 1 ]; then
		pgpKeyVersion="${version%.*}.$(( minor + 1 ))"
	fi
	pgp="$(jq -c --argjson pgp "$pgp" '$pgp + [ .[env.pgpKeyVersion] // error("missing PGP key for \(env.pgpKeyVersion)") ]' pgp-keys.json)"

	json="$(
		{
			jq <<<"$json" -c .
			_jq --argjson pgp "$pgp" '{ (env.version): (
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
					pgp: $pgp,
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
										"debian12": "debian:bookworm-slim",
										"debian13": "debian:trixie-slim",
										"debian14": "debian:forky-slim",
										"ubuntu1604": "ubuntu:xenial",
										"ubuntu1804": "ubuntu:bionic",
										"ubuntu2004": "ubuntu:focal",
										"ubuntu2204": "ubuntu:jammy",
										"ubuntu2404": "ubuntu:noble",
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
						"windowsservercore-ltsc2022",
						"windowsservercore-1809",
						"nanoserver-ltsc2022",
						"nanoserver-1809"
					],
					features: ([
						# https://github.com/mongodb/mongo/blob/r6.0.0/src/mongo/installer/msi/wxs/FeatureFragment.wxs#L9-L85 (no Client)
						# https://github.com/mongodb/mongo/blob/r4.4.2/src/mongo/installer/msi/wxs/FeatureFragment.wxs#L9-L92 (no MonitoringTools,ImportExportTools)
						"ServerNoService",
						if [ "5.0" ] | index(env.version | rtrimstr("-rc")) then
							"Client"
						else empty end,
						"Router",
						"MiscellaneousTools",
						empty
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

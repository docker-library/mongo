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

			# inject upstream EOL dates
			| .meta.eol = (
				.version
				| rtrimstr("-rc")
				| {
					# https://www.mongodb.com/support-policy/lifecycles
					# (only needs to list versions that currently exist in "current.json" that we are scraping, and only because they do not get removed promptly at EOL)

					"8.0": "2029-10-31",
					"7.0": "2027-08-31",
					"6.0": "2025-07-31",
					"5.0": "2024-10-31",
					"4.4": "2024-02-29",

					# "Rapid Releases" and "Minor Releases"
					"8.2": "2026-03-30",
				}[.]
			)
			# ... so we can filter out EOL versions (because "current.json" continues to list them for some period of time, but with no explicitly differentiating metadata about their EOL state)
			| select(
				.meta.eol
				| not or . >= (now | strftime("%Y-%m-%d"))
				# (ie, only keep versions whose EOL status is unknown because we need to update the table above or versions we know are not yet EOL)
			)
		]

		# in case of duplicates that map to the same "X.Y[-rc]", prefer the first one (the upstream file is typically in descending sorted order, so we do not need to get much more complicated than this)
		# *not* doing this was actually totally fine/sane up until 2024-08-14, because prior to that there were never any duplicates in the upstream file so everything "just worked"
		# on 2024-08-14, upstream released 7.0.14-rc0, but (accidentally?) left 7.0.13-rc1 listed in the file, and without this fix, we prefer the later entry due to how we export the data below
		| unique_by(.version)

		# now convert all that data to a basic shell list + map so we can loop over/use it appropriately
		| "allVersions=( " + (
			map(.version | ., if endswith("-rc") then rtrimstr("-rc") else . + "-rc" end)
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

	json="$(
		{
			jq <<<"$json" -c .
			_jq --slurpfile pgpKeys pgp-keys.json '{ (env.version): (
				$pgpKeys[0] as $pgp
				| (env.version | rtrimstr("-rc")) as $rcVersion
				| with_entries(select(IN(.key;
					# interesting bits of raw upstream metadata
					"changes",
					"date",
					"githash",
					"notes",
					"version",
					"eol", # not exactly "upstream" metadata, but metadata from upstream that we carefully injected
					empty
				)))
				+ {
					pgp: [
						if env.version != $rcVersion then
							# the "testing" repository (used for RCs) has a dedicated PGP key (but still needs the "release" key for the release line)
							$pgp.dev
						else empty end,

						(
							$pgp[$rcVersion] # prefer an exact match (4.4 resurrection for CVE-2025-14847 "MongoBleed")
							// $pgp[$rcVersion | sub("[.][0-9]+$"; ".0")] # normalizing 8.x to 8.0 because "Rapid Releases" use the key of the most recent major
						),

						empty
					],
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
						"windowsservercore-ltsc2025",
						"windowsservercore-ltsc2022",
						#"nanoserver-ltsc2025", # The command "cmd /S /C mongod --version" returned a non-zero code: 3221225785
						"nanoserver-ltsc2022",
						empty # trailing comma
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

#!/usr/bin/env bash
set -Eeuo pipefail

declare -A aliases=(
	[8.0]='8 latest'
	[7.0]='7'
	[6.0]='6'
	[5.0]='5'
)

self="$(basename "$BASH_SOURCE")"
cd "$(dirname "$(readlink -f "$BASH_SOURCE")")"

if [ "$#" -eq 0 ]; then
	versions="$(jq -r 'to_entries | map(if .value then .key | @sh else empty end) | join(" ")' versions.json)"
	eval "set -- $versions"
fi

# sort version numbers with highest first
IFS=$'\n'; set -- $(sort -rV <<<"$*"); unset IFS

# get the most recent commit which modified any of "$@"
fileCommit() {
	git log -1 --format='format:%H' HEAD -- "$@"
}

# get the most recent commit which modified "$1/Dockerfile" or any file COPY'd from "$1/Dockerfile"
dirCommit() {
	local dir="$1"; shift
	(
		cd "$dir"
		fileCommit \
			Dockerfile \
			$(git show HEAD:./Dockerfile | awk '
				toupper($1) == "COPY" {
					for (i = 2; i < NF; i++) {
						print $i
					}
				}
			')
	)
}

getArches() {
	local repo="$1"; shift
	local officialImagesBase="${BASHBREW_LIBRARY:-https://github.com/docker-library/official-images/raw/HEAD/library}/"

	local parentRepoToArchesStr
	parentRepoToArchesStr="$(
		find -name 'Dockerfile' -exec awk -v officialImagesBase="$officialImagesBase" '
				toupper($1) == "FROM" && $2 !~ /^('"$repo"'|scratch|.*\/.*)(:|$)/ {
					printf "%s%s\n", officialImagesBase, $2
				}
			' '{}' + \
			| sort -u \
			| xargs -r bashbrew cat --format '["{{ .RepoName }}:{{ .TagName }}"]="{{ join " " .TagEntry.Architectures }}"'
	)"
	eval "declare -g -A parentRepoToArches=( $parentRepoToArchesStr )"
}
getArches 'mongo'

cat <<-EOH
# this file is generated via https://github.com/docker-library/mongo/blob/$(fileCommit "$self")/$self

Maintainers: Tianon Gravi <admwiggin@gmail.com> (@tianon),
             Joseph Ferguson <yosifkit@gmail.com> (@yosifkit)
GitRepo: https://github.com/docker-library/mongo.git
EOH

# prints "$2$1$3$1...$N"
join() {
	local sep="$1"; shift
	local out; printf -v out "${sep//%/%%}%s" "$@"
	echo "${out#$sep}"
}

for version; do
	rcVersion="${version%-rc}"
	export version rcVersion

	if ! fullVersion="$(jq -er '.[env.version] | if . then .version else empty end' versions.json)"; then
		continue
	fi

	if [ "$rcVersion" != "$version" ] && [ -e "$rcVersion/Dockerfile" ]; then
		# if this is a "-rc" release, let's make sure the release it contains isn't already GA (and thus something we should not publish anymore)
		rcFullVersion="$(jq -r '.[env.rcVersion].version' versions.json)"
		latestVersion="$({ echo "$fullVersion"; echo "$rcFullVersion"; } | sort -V | tail -1)"
		if [[ "$fullVersion" == "$rcFullVersion"* ]] || [ "$latestVersion" = "$rcFullVersion" ]; then
			# "x.y.z-rc1" == x.y.z*
			continue
		fi
	fi

	versionAliases=(
		$fullVersion
		$version
		${aliases[$version]:-}
	)

	variants="$(jq -r '.[env.version].targets.windows.variants | [""] + map("windows/" + .) | map(@sh) | join(" ")' versions.json)"
	eval "variants=( $variants )"

	for v in "${variants[@]}"; do
		dir="$version${v:+/$v}"
		commit="$(dirCommit "$dir")"

		if [ -z "$v" ]; then
			variant="$(jq -r '.[env.version] | .targets[.linux].suite' versions.json)" # "bionic", etc.
		else
			variant="$(basename "$v")" # windowsservercore-1809, etc.
		fi

		variantAliases=( "${versionAliases[@]/%/-$variant}" )
		variantAliases=( "${variantAliases[@]//latest-/}" )

		sharedTags=()
		for windowsShared in windowsservercore nanoserver; do
			if [[ "$variant" == "$windowsShared"* ]]; then
				sharedTags=( "${versionAliases[@]/%/-$windowsShared}" )
				sharedTags=( "${sharedTags[@]//latest-/}" )
				break
			fi
		done
		if [[ "$variant" == 'windowsservercore'* ]] || [ -z "$v" ]; then
			sharedTags+=( "${versionAliases[@]}" )
		fi

		case "$v" in
			windows/*)
				# this is the really long way to say "windows-amd64"
				variantArches="$(jq -r '.[env.version] | .targets.windows.arches | map("windows-" + . | @sh) | join(" ")' versions.json)"
				;;
			*)
				variantArches="$(jq -r '.[env.version] | .targets[.linux].arches | map(@sh) | join(" ")' versions.json)"
				;;
		esac
		eval "variantArches=( $variantArches )"

		constraints=
		if [ -n "$v" ]; then
			constraints="$variant"
			if [[ "$variant" == nanoserver-* ]]; then
				# nanoserver variants "COPY --from=...:...-windowsservercore-... ..."
				constraints+=", windowsservercore-${variant#nanoserver-}"
			fi
		fi

		echo
		echo "Tags: $(join ', ' "${variantAliases[@]}")"
		if [ "${#sharedTags[@]}" -gt 0 ]; then
			echo "SharedTags: $(join ', ' "${sharedTags[@]}")"
		fi
		cat <<-EOE
			Architectures: $(join ', ' "${variantArches[@]}")
			GitCommit: $commit
			Directory: $dir
		EOE
		[ -z "$constraints" ] || echo "Constraints: $constraints"
	done
done

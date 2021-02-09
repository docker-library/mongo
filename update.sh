#!/usr/bin/env bash
set -Eeuo pipefail

cd "$(dirname "$(readlink -f "$BASH_SOURCE")")"

versions=( "$@" )
if [ ${#versions[@]} -eq 0 ]; then
	versions=( */ )
fi
versions=( "${versions[@]%/}" )

defaultFrom='ubuntu:bionic'
declare -A froms=(
	[3.6]='ubuntu:xenial'
	[4.0]='ubuntu:xenial'
)

declare -A fromToCommunityVersionsTarget=(
	[ubuntu:bionic]='ubuntu1804'
	[ubuntu:xenial]='ubuntu1604'
)

declare -A dpkgArchToBashbrew=(
	[amd64]='amd64'
	[armel]='arm32v5'
	[armhf]='arm32v7'
	[arm64]='arm64v8'
	[i386]='i386'
	[ppc64el]='ppc64le'
	[s390x]='s390x'
)

communityVersions="$(
	curl -fsSL 'https://downloads.mongodb.org/current.json' \
		| jq -c '.versions[]'
)"

for version in "${versions[@]}"; do
	rcVersion="${version%-rc}"
	major="$rcVersion"
	rcJqNot='| not'
	if [ "$rcVersion" != "$version" ]; then
		rcJqNot=
		major='testing'
	fi

	from="${froms[$version]:-$defaultFrom}"
	distro="${from%%:*}" # "debian", "ubuntu"
	suite="${from#$distro:}" # "jessie-slim", "xenial"
	suite="${suite%-slim}" # "jessie", "xenial"

	downloads="$(
		jq -c --arg rcVersion "$rcVersion" '
			select(
				(.version | startswith($rcVersion + "."))
				and (.version | contains("-rc") '"$rcJqNot"')
			)
			| .version as $version
			| .downloads[]
			| select(.arch == "x86_64")
			| .version = $version
		' <<<"$communityVersions"
	)"
	versions="$(
		jq -r --arg target "${fromToCommunityVersionsTarget[$from]}" '
			select(.edition == "targeted" and .target // "" == $target)
			| .version
		' <<<"$downloads"
	)"
	windowsDownloads="$(
		jq -c '
			select(
				.edition == "base"
				and (.target // "" | test("^windows(_x86_64-(2008plus-ssl|2012plus))?$"))
			)
		' <<<"$downloads"
	)"
	windowsVersions="$(
		jq -r '.version' <<<"$windowsDownloads"
	)"
	commonVersions="$(
		comm -12 \
			<(sort -u <<<"$versions") \
			<(sort -u <<<"$windowsVersions")
	)"
	fullVersion="$(sort -V <<< "$commonVersions" | tail -1)"

	if [ -z "$fullVersion" ]; then
		echo >&2 "error: failed to find full version for $version"
		exit 1
	fi

	echo "$version: $fullVersion"

	tilde='~'
	debVersion="${fullVersion//-/$tilde}"
	component='multiverse'
	if [ "$distro" = 'debian' ]; then
		component='main'
	fi
	repoUrlBase="https://repo.mongodb.org/apt/$distro/dists/$suite/mongodb-org/$major/$component"

	_arch_has_version() {
		local arch="$1"; shift
		local version="$1"; shift
		curl -fsSL "$repoUrlBase/binary-$arch/Packages.gz" 2>/dev/null \
			| gunzip 2>/dev/null \
			| awk -F ': ' -v version="$version" '
				BEGIN { ret = 1 }
				$1 == "Package" { pkg = $2 }
				pkg ~ /^mongodb-(org(-unstable)?|10gen)$/ && $1 == "Version" && $2 == version { print pkg; ret = 0; last }
				END { exit(ret) }
			'
	}

	arches=()
	packageName=
	for dpkgArch in "${!dpkgArchToBashbrew[@]}"; do
		bashbrewArch="${dpkgArchToBashbrew[$dpkgArch]}"
		if archPackageName="$(_arch_has_version "$dpkgArch" "$debVersion")"; then
			if [ -z "$packageName" ]; then
				packageName="$archPackageName"
			elif [ "$archPackageName" != "$packageName" ]; then
				echo >&2 "error: package name for $dpkgArch ($archPackageName) does not match other arches ($packageName)"
				exit 1
			fi
			arches+=( "$bashbrewArch" )
		fi
	done
	sortedArches="$(xargs -n1 <<<"${arches[*]}" | sort | xargs)"
	if [ -z "$sortedArches" ]; then
		echo >&2 "error: version $version is missing $distro ($suite) packages!"
		exit 1
	fi

	echo "- $sortedArches"

	if [ "$major" != 'testing' ]; then
		gpgKeyVersion="$rcVersion"
		minor="${rcVersion#*.}" # "4.3" -> "3"
		if [ "$(( minor % 2 ))" = 1 ]; then
			gpgKeyVersion="${rcVersion%.*}.$(( minor + 1 ))"
		fi
		gpgKeys="$(grep "^$gpgKeyVersion:" gpg-keys.txt | cut -d: -f2)"
	else
		# the "testing" repository (used for RCs) could be signed by any of the GPG keys used by the project
		gpgKeys="$(grep -E '^[0-9.]+:' gpg-keys.txt | cut -d: -f2 | xargs)"
	fi

	sed -r \
		-e 's/^(ENV MONGO_MAJOR) .*/\1 '"$major"'/' \
		-e 's/^(ENV MONGO_VERSION) .*/\1 '"$debVersion"'/' \
		-e 's/^(ARG MONGO_PACKAGE)=.*/\1='"$packageName"'/' \
		-e 's/^(FROM) .*/\1 '"$from"'/' \
		-e 's/%%DISTRO%%/'"$distro"'/' \
		-e 's/%%SUITE%%/'"$suite"'/' \
		-e 's/%%COMPONENT%%/'"$component"'/' \
		-e 's!%%ARCHES%%!'"$sortedArches"'!g' \
		-e 's/^(ENV GPG_KEYS) .*/\1 '"$gpgKeys"'/' \
		Dockerfile-linux.template \
		> "$version/Dockerfile"

	cp -a docker-entrypoint.sh "$version/"

	windowsMsi="$(
		jq -r --arg version "$fullVersion" '
			select(.version == $version)
			| .msi
		' <<<"$windowsDownloads" | head -1
	)"
	[ -n "$windowsMsi" ]

	# 4.3 doesn't seem to have a sha256 file (403 forbidden), so this has to be optional :(
	windowsSha256="$(curl -fsSL "$windowsMsi.sha256" | cut -d' ' -f1 || :)"

	# https://github.com/mongodb/mongo/blob/r4.4.2/src/mongo/installer/msi/wxs/FeatureFragment.wxs#L9-L92 (no MonitoringTools,ImportExportTools)
	# https://github.com/mongodb/mongo/blob/r4.2.11/src/mongo/installer/msi/wxs/FeatureFragment.wxs#L9-L116
	# https://github.com/mongodb/mongo/blob/r4.0.21/src/mongo/installer/msi/wxs/FeatureFragment.wxs#L9-L128
	# https://github.com/mongodb/mongo/blob/r3.6.21/src/mongo/installer/msi/wxs/FeatureFragment.wxs#L9-L102 (no ServerNoService, only Server)
	windowsFeatures='ServerNoService,Client,Router,MiscellaneousTools'
	case "$rcVersion" in
		4.2 | 4.0 | 3.6) windowsFeatures+=',MonitoringTools,ImportExportTools' ;;
	esac
	if [ "$rcVersion" = '3.6' ]; then
		windowsFeatures="${windowsFeatures//ServerNoService/Server}"
	fi

	for winVariant in \
		windowsservercore-{1809,ltsc2016} \
	; do
		mkdir -p "$version/windows/$winVariant"

		sed -r \
			-e 's/^(ENV MONGO_VERSION) .*/\1 '"$fullVersion"'/' \
			-e 's!^(ENV MONGO_DOWNLOAD_URL) .*!\1 '"$windowsMsi"'!' \
			-e 's/^(ENV MONGO_DOWNLOAD_SHA256)=.*/\1='"$windowsSha256"'/' \
			-e 's!^(FROM .+):.+!\1:'"${winVariant#*-}"'!' \
			-e 's!(ADDLOCAL)=placeholder!\1='"$windowsFeatures"'!' \
			Dockerfile-windows.template \
			> "$version/windows/$winVariant/Dockerfile"
	done
done

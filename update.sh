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

declare -A dpkgArchToBashbrew=(
	[amd64]='amd64'
	[armel]='arm32v5'
	[armhf]='arm32v7'
	[arm64]='arm64v8'
	[i386]='i386'
	[ppc64el]='ppc64le'
	[s390x]='s390x'
)

travisEnv=
appveyorEnv=
for version in "${versions[@]}"; do
	rcVersion="${version%-rc}"
	major="$rcVersion"
	rcGrepV='-v'
	if [ "$rcVersion" != "$version" ]; then
		rcGrepV=
		major='testing'
	fi

	from="${froms[$version]:-$defaultFrom}"
	distro="${from%%:*}" # "debian", "ubuntu"
	suite="${from#$distro:}" # "jessie-slim", "xenial"
	suite="${suite%-slim}" # "jessie", "xenial"

	component='multiverse'
	if [ "$distro" = 'debian' ]; then
		component='main'
	fi

	repoUrlBase="https://repo.mongodb.org/apt/$distro/dists/$suite/mongodb-org/$major/$component"

	_arch_versions() {
		local arch="$1"; shift
		curl -fsSL "$repoUrlBase/binary-$arch/Packages.gz" 2>/dev/null \
			| gunzip 2>/dev/null \
			| awk -F ': ' '
				$1 == "Package" { pkg = $2 }
				pkg ~ /^mongodb-(org(-unstable)?|10gen)$/ && $1 == "Version" { print $2 "=" pkg }
			' \
			| grep "^$rcVersion\." \
			| grep -vE '~pre~$' \
			| sort -V \
			| tac|tac
	}

	fullVersion="$(_arch_versions 'amd64' | tail -1)"
	packageName="${fullVersion#*=}"
	fullVersion="${fullVersion%=$packageName}"
	if [ -z "$fullVersion" ]; then
		echo >&2 "error: failed to get full version for '$version' (from '$repoUrlBase')"
		exit 1
	fi

	arches=()
	for dpkgArch in "${!dpkgArchToBashbrew[@]}"; do
		bashbrewArch="${dpkgArchToBashbrew[$dpkgArch]}"
		if \
			[ "$bashbrewArch" = 'amd64' ] \
			|| grep -qx "$fullVersion=$packageName" <(_arch_versions "$dpkgArch") \
		; then
			arches+=( "$bashbrewArch" )
		fi
	done
	sortedArches="$(xargs -n1 <<<"${arches[*]}" | sort | xargs)"

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

	echo "$version: $fullVersion (linux; $sortedArches)"

	sed -r \
		-e 's/^(ENV MONGO_MAJOR) .*/\1 '"$major"'/' \
		-e 's/^(ENV MONGO_VERSION) .*/\1 '"$fullVersion"'/' \
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

	if [ -d "$version/windows" ]; then
		# https://github.com/mkevenaar/chocolatey-packages/blob/8c38398f695e86c55793ee9d61f4e541a25ce0be/automatic/mongodb.install/update.ps1#L15-L31
		windowsDownloads="$(
			curl -fsSL 'https://www.mongodb.com/download-center/community' \
				| grep -oiE '"server-data">window[.]__serverData = {(.+?)}<' \
				| cut -d= -f2- | cut -d'<' -f1 \
				| jq -r --arg rcVersion "$rcVersion" '
					.community.versions[]
					| select(.version | startswith($rcVersion + "."))
					| .downloads[]
					| select(
						.edition == "base"
						and .arch == "x86_64"
						and (.target // "" | test("^windows(_x86_64-(2008plus-ssl|2012plus))?$"))
					)
					| .msi
				' \
				| grep -vE -- '-rc'
		)"
		windowsLatest="$(head -1 <<<"$windowsDownloads")"
		windowsVersion="$(sed -r -e "s!^https?://.+-(${rcVersion//./\\.}\.[^\"]+)-signed.msi\$!\1!" <<<"$windowsLatest")"

		# 4.3 doesn't seem to have a sha256 file (403 forbidden), so this has to be optional :(
		windowsSha256="$(curl -fsSL "$windowsLatest.sha256" | cut -d' ' -f1 || :)"

		echo "$version: $windowsVersion (windows)"

		for winVariant in \
			windowsservercore-{1809,ltsc2016} \
		; do
			[ -d "$version/windows/$winVariant" ] || continue

			sed -r \
				-e 's/^(ENV MONGO_VERSION) .*/\1 '"$windowsVersion"'/' \
				-e 's!^(ENV MONGO_DOWNLOAD_URL) .*!\1 '"$windowsLatest"'!' \
				-e 's/^(ENV MONGO_DOWNLOAD_SHA256)=.*/\1='"$windowsSha256"'/' \
				-e 's!^(FROM .+):.+!\1:'"${winVariant#*-}"'!' \
				Dockerfile-windows.template \
				> "$version/windows/$winVariant/Dockerfile"

			case "$winVariant" in
				# https://www.appveyor.com/docs/windows-images-software/
				*-1809)
					appveyorEnv='\n    - version: '"$version"'\n      variant: '"$winVariant"'\n      APPVEYOR_BUILD_WORKER_IMAGE: Visual Studio 2019'"$appveyorEnv"
					;;
				*-ltsc2016)
					appveyorEnv='\n    - version: '"$version"'\n      variant: '"$winVariant"'\n      APPVEYOR_BUILD_WORKER_IMAGE: Visual Studio 2017'"$appveyorEnv"
					;;
			esac
		done
	fi

	travisEnv='\n    - os: linux\n      env: VERSION='"$version$travisEnv"
done

travis="$(awk -v 'RS=\n\n' '$1 == "matrix:" { $0 = "matrix:\n  include:'"$travisEnv"'" } { printf "%s%s", $0, RS }' .travis.yml)"
echo "$travis" > .travis.yml

appveyor="$(awk -v 'RS=\n\n' '$1 == "environment:" { $0 = "environment:\n  matrix:'"$appveyorEnv"'" } { printf "%s%s", $0, RS }' .appveyor.yml)"
echo "$appveyor" > .appveyor.yml

#!/usr/bin/env bash
set -Eeuo pipefail

cd "$(dirname "$(readlink -f "$BASH_SOURCE")")"

versions=( "$@" )
if [ ${#versions[@]} -eq 0 ]; then
	versions=( */ )
fi
versions=( "${versions[@]%/}" )

defaultFrom='ubuntu:xenial'
declare -A froms=(
	[3.4]='debian:jessie-slim'
	[3.6]='debian:stretch-slim'
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

	packagesUrl="https://repo.mongodb.org/apt/$distro/dists/$suite/mongodb-org/$major/$component/binary-amd64/Packages"
	fullVersion="$(
		curl -fsSL "$packagesUrl.gz" \
			| gunzip \
			| awk -F ': ' '
				$1 == "Package" { pkg = $2 }
				pkg ~ /^mongodb-(org(-unstable)?|10gen)$/ && $1 == "Version" { print $2 "=" pkg }
			' \
			| grep "^$rcVersion\." \
			| grep -v '~pre~$' \
			| sort -V \
			| tail -1
	)"
	packageName="${fullVersion#*=}"
	fullVersion="${fullVersion%=$packageName}"

	gpgKeyVersion="$rcVersion"
	minor="${major#*.}" # "4.3" -> "3"
	if [ "$(( minor % 2 ))" = 1 ]; then
		gpgKeyVersion="${major%.*}.$(( minor + 1 ))"
	fi
	gpgKeys="$(grep "^$gpgKeyVersion:" gpg-keys.txt | cut -d: -f2)"

	echo "$version: $fullVersion (linux)"

	sed -r \
		-e 's/^(ENV MONGO_MAJOR) .*/\1 '"$major"'/' \
		-e 's/^(ENV MONGO_VERSION) .*/\1 '"$fullVersion"'/' \
		-e 's/^(ARG MONGO_PACKAGE)=.*/\1='"$packageName"'/' \
		-e 's/^(FROM) .*/\1 '"$from"'/' \
		-e 's/%%DISTRO%%/'"$distro"'/' \
		-e 's/%%SUITE%%/'"$suite"'/' \
		-e 's/%%COMPONENT%%/'"$component"'/' \
		-e 's/^(ENV GPG_KEYS) .*/\1 '"$gpgKeys"'/' \
		Dockerfile-linux.template \
		> "$version/Dockerfile"

	if [ "$version" != '3.4' ]; then
		sed -ri -e '/backwards compat/d' "$version/Dockerfile"
	fi

	cp -a docker-entrypoint.sh "$version/"

	if [ -d "$version/windows" ]; then
		windowsVersions="$(
			curl -fsSL 'https://www.mongodb.org/dl/win32/x86_64' \
				| grep --extended-regexp --only-matching '"https?://[^"]+/win32/mongodb-win32-x86_64-(2008plus-ssl|2012plus)-'"${rcVersion//./\\.}"'\.[^"]+-signed.msi"' \
				| sed \
					-e 's!^"!!' \
					-e 's!"$!!' \
					-e 's!http://downloads.mongodb.org/!https://downloads.mongodb.org/!' \
				| grep $rcGrepV -E -- '-rc[0-9]'
		)"
		windowsLatest="$(echo "$windowsVersions" | head -1)"
		windowsSha256="$(curl -fsSL "$windowsLatest.sha256" | cut -d' ' -f1)"
		windowsVersion="$(echo "$windowsLatest" | sed -r -e "s!^https?://.+(${rcVersion//./\\.}\.[^\"]+)-signed.msi\$!\1!")"

		echo "$version: $windowsVersion (windows)"

		for winVariant in \
			windowsservercore-{1803,1709,ltsc2016} \
		; do
			[ -d "$version/windows/$winVariant" ] || continue

			sed -r \
				-e 's/^(ENV MONGO_VERSION) .*/\1 '"$windowsVersion"'/' \
				-e 's!^(ENV MONGO_DOWNLOAD_URL) .*!\1 '"$windowsLatest"'!' \
				-e 's/^(ENV MONGO_DOWNLOAD_SHA256) .*/\1 '"$windowsSha256"'/' \
				-e 's!^FROM .*!FROM microsoft/'"${winVariant%%-*}"':'"${winVariant#*-}"'!' \
				Dockerfile-windows.template \
				> "$version/windows/$winVariant/Dockerfile"

			if [ "$version" = '3.4' ]; then
				sed -ri -e 's/, "--bind_ip_all"//' "$version/windows/$winVariant/Dockerfile"
			fi

			case "$winVariant" in
				*-1803) travisEnv='\n    - os: windows\n      dist: 1803-containers\n      env: VERSION='"$version VARIANT=windows/$winVariant$travisEnv" ;;
				*-1709) ;; # no AppVeyor or Travis support for 1709: https://github.com/appveyor/ci/issues/1885
				*) appveyorEnv='\n    - version: '"$version"'\n      variant: '"$winVariant$appveyorEnv" ;;
			esac
		done
	fi

	travisEnv='\n    - os: linux\n      env: VERSION='"$version$travisEnv"
done

travis="$(awk -v 'RS=\n\n' '$1 == "matrix:" { $0 = "matrix:\n  include:'"$travisEnv"'" } { printf "%s%s", $0, RS }' .travis.yml)"
echo "$travis" > .travis.yml

appveyor="$(awk -v 'RS=\n\n' '$1 == "environment:" { $0 = "environment:\n  matrix:'"$appveyorEnv"'" } { printf "%s%s", $0, RS }' .appveyor.yml)"
echo "$appveyor" > .appveyor.yml

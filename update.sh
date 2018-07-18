#!/usr/bin/env bash
set -Eeuo pipefail

cd "$(dirname "$(readlink -f "$BASH_SOURCE")")"

versions=( "$@" )
if [ ${#versions[@]} -eq 0 ]; then
	versions=( */ )
fi
versions=( "${versions[@]%/}" )

# TODO do something with https://www.mongodb.org/dl/linux/x86_64 instead of scraping the APT repo contents
# (but then have to solve hard "release candidate" problems; ie, if we have 2.6.4 and 2.6.5-rc0 comes out, we don't want 2.6 to switch over to the RC)

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

	from="$(gawk -F '[[:space:]]+' 'toupper($1) == "FROM" { print $2; exit }' "$version/Dockerfile")" # "debian:xxx"
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

	(
		set -x
		sed -ri \
			-e 's/^(ENV MONGO_MAJOR) .*/\1 '"$major"'/' \
			-e 's/^(ENV MONGO_VERSION) .*/\1 '"$fullVersion"'/' \
			-e 's/^(ARG MONGO_PACKAGE)=.*/\1='"$packageName"'/' \
			"$version/Dockerfile"
	)

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

		(
			set -x
			sed -ri \
				-e 's/^(ENV MONGO_VERSION) .*/\1 '"$windowsVersion"'/' \
				-e 's!^(ENV MONGO_DOWNLOAD_URL) .*!\1 '"$windowsLatest"'!' \
				-e 's/^(ENV MONGO_DOWNLOAD_SHA256) .*/\1 '"$windowsSha256"'/' \
				"$version/windows/"*"/Dockerfile"
		)

		for winVariant in \
			nanoserver-{1803,1709,sac2016} \
			windowsservercore-{1803,1709,ltsc2016} \
		; do
			[ -f "$version/windows/$winVariant/Dockerfile" ] || continue

			sed -ri \
				-e 's!^FROM .*!FROM microsoft/'"${winVariant%%-*}"':'"${winVariant#*-}"'!' \
				"$version/windows/$winVariant/Dockerfile"

			case "$winVariant" in
				*-1709 | *-1803) ;; # no AppVeyor support for 1709+ yet: https://github.com/appveyor/ci/issues/1885
				*) appveyorEnv='\n    - version: '"$version"'\n      variant: '"$winVariant$appveyorEnv" ;;
			esac
		done
	fi

	travisEnv='\n  - VERSION='"$version$travisEnv"
done

travis="$(awk -v 'RS=\n\n' '$1 == "env:" { $0 = "env:'"$travisEnv"'" } { printf "%s%s", $0, RS }' .travis.yml)"
echo "$travis" > .travis.yml

appveyor="$(awk -v 'RS=\n\n' '$1 == "environment:" { $0 = "environment:\n  matrix:'"$appveyorEnv"'" } { printf "%s%s", $0, RS }' .appveyor.yml)"
echo "$appveyor" > .appveyor.yml

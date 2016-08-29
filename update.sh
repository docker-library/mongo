#!/bin/bash
set -eo pipefail

cd "$(dirname "$(readlink -f "$BASH_SOURCE")")"

versions=( "$@" )
if [ ${#versions[@]} -eq 0 ]; then
	versions=( */ )
fi
versions=( "${versions[@]%/}" )

# TODO do something with https://www.mongodb.org/dl/linux/x86_64 instead of scraping the APT repo contents
# (but then have to solve hard "release candidate" problems; ie, if we have 2.6.4 and 2.6.5-rc0 comes out, we don't want 2.6 to switch over to the RC)

travisEnv=
for version in "${versions[@]}"; do
	rcVersion="${version%-rc}"
	major="$rcVersion"
	rcGrepV='-v'
	if [ "$rcVersion" != "$version" ]; then
		rcGrepV=
		major='testing'
	fi

	from="$(awk -F '[[:space:]]+' 'toupper($1) == "FROM" { print $2; exit }' "$version/Dockerfile")" # "debian:xxx"
	suite="${from#*:}" # "wheezy" or "jessie"

	if [ "${version%%.*}" -ge 3 ]; then
		packagesUrl="http://repo.mongodb.org/apt/debian/dists/$suite/mongodb-org/$major/main/binary-amd64/Packages"
	else
		packagesUrl='http://downloads-distro.mongodb.org/repo/debian-sysvinit/dists/dist/10gen/binary-amd64/Packages'
	fi
	fullVersion="$(
		curl -fsSL "$packagesUrl.gz" \
			| gunzip \
			| awk -F ': ' '
				$1 == "Package" { pkg = $2 }
				pkg ~ /^mongodb-(org(-unstable)?|10gen)$/ && $1 == "Version" { print $2 }
			' \
			| grep "^$rcVersion\." \
			| grep -v '~pre~$' \
			| sort -V \
			| tail -1
	)"

	(
		set -x
		sed -ri \
			-e 's/^(ENV MONGO_MAJOR) .*/\1 '"$major"'/' \
			-e 's/^(ENV MONGO_VERSION) .*/\1 '"$fullVersion"'/' \
			"$version/Dockerfile"
	)

	if [ -d "$version/windows" ]; then
		windowsUrlPrefix='http://downloads.mongodb.org/win32/mongodb-win32-x86_64-2008plus-ssl-'
		windowsUrlSuffix='-signed.msi'
		windowsVersions="$(
			curl -fsSL 'https://www.mongodb.org/dl/win32/x86_64-2008plus-ssl' \
				| grep --extended-regexp --only-matching '"'"${windowsUrlPrefix}${rcVersion//./\\.}"'\.[^"]+'"${windowsUrlSuffix}"'"' \
				| sed \
					-e 's!^"'"$windowsUrlPrefix"'!!' \
					-e 's!'"$windowsUrlSuffix"'"$!!' \
				| grep $rcGrepV -- '-rc'
		)"
		windowsLatest="$(echo "$windowsVersions" | head -1)"
		windowsSha256="$(curl -fsSL "${windowsUrlPrefix}${windowsLatest}${windowsUrlSuffix}.sha256" | cut -d' ' -f1)"

		(
			set -x
			sed -ri \
				-e 's/^(ENV MONGO_VERSION) .*/\1 '"$windowsLatest"'/' \
				-e 's/^(ENV MONGO_DOWNLOAD_SHA256) .*/\1 '"$windowsSha256"'/' \
				"$version/windows/"*"/Dockerfile"
		)
	fi

	travisEnv='\n  - VERSION='"$version$travisEnv"
done

travis="$(awk -v 'RS=\n\n' '$1 == "env:" { $0 = "env:'"$travisEnv"'" } { printf "%s%s", $0, RS }' .travis.yml)"
echo "$travis" > .travis.yml

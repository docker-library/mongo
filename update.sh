#!/bin/bash
set -e

declare -A gpgKeys
gpgKeys=(
	[2.2]='3AFEF01FE92B6927CC1EEC80F564179A36496327'
	[2.4]='CEA1E18DDA77EF4E67884FF2A6982D0160456C5A'
	[2.6]='DFFA3DCF326E302C4787673A01C4E7FAAAB2461C'
	[3.0]='BDC0DB28022D7DEA1490DC3E7085801C857FD301'
	
	# unstable releases share their "major" tag's key
	[2.1]='3AFEF01FE92B6927CC1EEC80F564179A36496327'
	[2.3]='CEA1E18DDA77EF4E67884FF2A6982D0160456C5A'
	[2.5]='DFFA3DCF326E302C4787673A01C4E7FAAAB2461C'
	[2.7]='BDC0DB28022D7DEA1490DC3E7085801C857FD301'
)
# see https://www.mongodb.org/static/pgp/server-2.6.asc etc.

cd "$(dirname "$(readlink -f "$BASH_SOURCE")")"

versions=( "$@" )
if [ ${#versions[@]} -eq 0 ]; then
	versions=( */ )
fi
versions=( "${versions[@]%/}" )

# TODO do something with https://www.mongodb.org/dl/linux/x86_64 instead, but have to solve hard "release candidate" problems (ie, if we have 2.6.4 and 2.6.5-rc0 comes out, we don't want 2.6 to switch over to the RC)

packagesUrl='http://downloads-distro.mongodb.org/repo/debian-sysvinit/dists/dist/10gen/binary-amd64/Packages'
packages="$(echo "$packagesUrl" | sed -r 's/[^a-zA-Z.-]+/-/g')"
curl -sSL "${packagesUrl}.gz" | gunzip > "$packages"

for version in "${versions[@]}"; do
	fullVersion="$(grep -EA10 '^Package: mongodb-(org(-unstable)?|10gen)$' "$packages" | grep "^Version: $version\." | cut -d' ' -f2 | sort -V | tail -1)"
	gpgKey="${gpgKeys[$version]}"
	if [ -z "$gpgKey" ]; then
		echo >&2 "ERROR: missing GPG key fingerprint for $version; try:"
		echo >&2 "  curl -sSL 'https://www.mongodb.org/static/pgp/server-$version.asc' | gpg --with-fingerprint -"
		exit 1
	fi
	(
		set -x
		[ -z "$fullVersion" ] || sed -ri 's/^(ENV MONGO_VERSION) .*/\1 '"$fullVersion"'/' "$version/Dockerfile"
		sed -ri 's/^(ENV MONGO_RELEASE_FINGERPRINT) .*/\1 '"$gpgKey"'/' "$version/Dockerfile"
	)
done

rm "$packages"

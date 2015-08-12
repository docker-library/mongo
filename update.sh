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
	if [ "${version%%.*}" -ge 3 ]; then
		packagesUrl="http://repo.mongodb.org/apt/debian/dists/wheezy/mongodb-org/$version/main/binary-amd64/Packages"
	else
		packagesUrl='http://downloads-distro.mongodb.org/repo/debian-sysvinit/dists/dist/10gen/binary-amd64/Packages'
	fi
	fullVersion="$(curl -sSL "$packagesUrl.gz" | gunzip | grep -EA10 '^Package: mongodb-(org(-unstable)?|10gen)$' | grep "^Version: $version\." | cut -d' ' -f2 | sort -V | tail -1)"
	(
		set -x
		sed -ri '
			s/^(ENV MONGO_MAJOR) .*/\1 '"$version"'/;
			s/^(ENV MONGO_VERSION) .*/\1 '"$fullVersion"'/;
		' "$version/Dockerfile"
	)
	
	travisEnv='\n  - VERSION='"$version$travisEnv"
done

travis="$(awk -v 'RS=\n\n' '$1 == "env:" { $0 = "env:'"$travisEnv"'" } { printf "%s%s", $0, RS }' .travis.yml)"
echo "$travis" > .travis.yml

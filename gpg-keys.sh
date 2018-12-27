#!/usr/bin/env bash
set -Eeuo pipefail

versions=( $(grep -vE '^#|^$' gpg-keys.txt | cut -d: -f1) )

for version in "${versions[@]}"; do
	fingerprints="$(
		docker run --rm -e v="$version" buildpack-deps:stretch-curl bash -Eeuo pipefail -xc '
			wget -O key.asc "https://www.mongodb.org/static/pgp/server-$v.asc" >&2
			gpg --batch --import key.asc >&2
			gpg --batch --fingerprint --with-colons | grep "^fpr:" | cut -d: -f10
		'
	)"
	awk -F: -v v="$version" -v fpr="$fingerprints" '
		$1 == v {
			printf "%s:%s\n", v, fpr
			next
		}
		{ print }
	' gpg-keys.txt > gpg-keys.txt.new
	mv gpg-keys.txt.new gpg-keys.txt
done

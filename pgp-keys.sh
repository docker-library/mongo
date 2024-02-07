#!/usr/bin/env bash
set -Eeuo pipefail

versions="$(jq -r 'keys_unsorted | map(@sh) | join(" ")' pgp-keys.json)"
eval "set -- $versions"

json='{}'

for version; do
	url="https://pgp.mongodb.com/server-$version.asc"
	export version url
	fingerprints="$(
		docker run --rm --env url buildpack-deps:bookworm-curl bash -Eeuo pipefail -xc '
			wget -O key.asc "$url" >&2
			gpg --batch --import key.asc >&2
			gpg --batch --fingerprint --with-colons | grep "^fpr:" | cut -d: -f10
		'
	)"
	export fingerprints
	json="$(jq <<<"$json" -c '
		.[env.version] = {
			url: env.url,
			fingerprints: (
				env.fingerprints
				| rtrimstr("\n")
				| split("\n")
			),
		}
	')"
done

jq <<<"$json" '
	to_entries
	| sort_by(.key | split(".") | map(tonumber? // .))
	| reverse
	| from_entries
' > pgp-keys.json

#!/usr/bin/env bash
set -Eeuo pipefail

versions="$(jq -r 'keys_unsorted | map(@sh) | join(" ")' pgp-keys.json)"
eval "set -- $versions"

json='{}'

for version; do
	fingerprints=
	# the key file for versions less than 9.0 are under major.minor.asc, but 9.0 is under major.asc instead
	for ver in "${version}" "${version%.*}"; do
		url="https://pgp.mongodb.com/server-$ver.asc"
		export version url
		if fingerprints="$(
			docker run --rm --env url buildpack-deps:bookworm-curl bash -Eeuo pipefail -xc '
				wget -O key.asc "$url" >&2
				gpg --batch --import key.asc >&2
				gpg --batch --fingerprint --with-colons | grep "^fpr:" | cut -d: -f10
			'
		)"; then
			break
		fi
	done
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

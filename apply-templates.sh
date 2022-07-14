#!/usr/bin/env bash
set -Eeuo pipefail

[ -f versions.json ] # run "versions.sh" first

jqt='.jq-template.awk'
if [ -n "${BASHBREW_SCRIPTS:-}" ]; then
	jqt="$BASHBREW_SCRIPTS/jq-template.awk"
elif [ "$BASH_SOURCE" -nt "$jqt" ]; then
	# https://github.com/docker-library/bashbrew/blob/master/scripts/jq-template.awk
	wget -qO "$jqt" 'https://github.com/docker-library/bashbrew/raw/9f6a35772ac863a0241f147c820354e4008edf38/scripts/jq-template.awk'
fi

if [ "$#" -eq 0 ]; then
	versions="$(jq -r 'keys | map(@sh) | join(" ")' versions.json)"
	eval "set -- $versions"
fi

generated_warning() {
	cat <<-EOH
		#
		# NOTE: THIS DOCKERFILE IS GENERATED VIA "apply-templates.sh"
		#
		# PLEASE DO NOT EDIT IT DIRECTLY.
		#

	EOH
}

for version; do
	rcVersion="${version%-rc}"
	export version rcVersion

	rm -rf "$version"

	if jq -e '.[env.version] | not' versions.json > /dev/null; then
		echo "skipping $version ..."
		continue
	fi

	echo "processing $version ..."

	mkdir -p "$version"
	{
		generated_warning
		gawk -f "$jqt" Dockerfile-linux.template
	} > "$version/Dockerfile"

	cp -a docker-entrypoint.sh "$version/"

	variants="$(jq -r '.[env.version].targets.windows.variants | map(@sh) | join(" ")' versions.json)"
	eval "variants=( $variants )"
	for variant in "${variants[@]}"; do
		windowsVariant="${variant%%-*}" # "windowsservercore", "nanoserver"
		windowsRelease="${variant#$windowsVariant-}" # "ltsc2022", "1809", etc
		windowsVariant="${windowsVariant#windows}" # "servercore", "nanoserver"
		export windowsVariant windowsRelease

		dir="$version/windows/$variant"
		echo "processing $dir ..."

		mkdir -p "$dir"
		{
			generated_warning
			gawk -f "$jqt" Dockerfile-windows.template
		} > "$dir/Dockerfile"
	done
done

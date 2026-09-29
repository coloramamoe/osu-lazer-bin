#!/bin/sh
set -eu

for command in curl python3 sha256sum sed grep mktemp; do
	command -v "$command" >/dev/null 2>&1 || {
		printf 'Missing required command: %s\n' "$command" >&2
		exit 1
	}
done

cd "$(dirname "$0")"
template=template
if [ -n "${GITHUB_TOKEN:-}" ]; then
	release=$(curl -fsSL -H "Authorization: Bearer ${GITHUB_TOKEN}" https://api.github.com/repos/ppy/osu/releases/latest)
else
	release=$(curl -fsSL https://api.github.com/repos/ppy/osu/releases/latest)
fi
tag=$(printf '%s' "$release" |
	python3 -c 'import json, sys; print(json.load(sys.stdin)["tag_name"])')
case "$tag" in
	*-lazer) ;;
	*) printf 'Unexpected release tag: %s\n' "$tag" >&2; exit 1 ;;
esac
version=${tag%-lazer}
printf '%s\n' "$version" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$' || {
	printf 'Unexpected release tag: %s\n' "$tag" >&2
	exit 1
}
old_version=$(sed -n 's/^version=//p' "$template")
if [ "$version" = "$old_version" ]; then
	if [ -n "${GITHUB_OUTPUT:-}" ]; then
		printf 'changed=false\nversion=%s\n' "$version" >> "$GITHUB_OUTPUT"
	fi
	exit 0
fi

appimage=$(mktemp)
new_template=$(mktemp)
trap 'rm -f "$new_template" "$appimage"' EXIT
trap 'exit 1' HUP INT TERM
curl -fL --retry 3 -o "$appimage" "https://github.com/ppy/osu/releases/download/${tag}/osu.AppImage"
checksum=$(sha256sum "$appimage")
checksum=${checksum%% *}
sed -e "s/^version=.*/version=$version/" \
	-e 's/^revision=.*/revision=1/' \
	-e "s/^checksum=.*/checksum=$checksum/" "$template" > "$new_template"
chmod 644 "$new_template"
mv "$new_template" "$template"
if [ -n "${GITHUB_OUTPUT:-}" ]; then
	printf 'changed=true\nversion=%s\n' "$version" >> "$GITHUB_OUTPUT"
fi
printf '%s\n' "$version"

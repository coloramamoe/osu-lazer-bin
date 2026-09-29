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
old_checksum=$(sed -n 's/^checksum=//p' "$template")
old_revision=$(sed -n 's/^revision=//p' "$template")
digest=$(printf '%s' "$release" |
	python3 -c 'import json, sys
assets = [asset for asset in json.load(sys.stdin)["assets"] if asset["name"] == "osu.AppImage"]
if len(assets) != 1:
    sys.exit("Expected one osu.AppImage release asset")
print(assets[0].get("digest") or "")')
case "$digest" in
	"") checksum= ;;
	sha256:*) checksum=${digest#sha256:} ;;
	*) printf 'Unexpected asset digest: %s\n' "$digest" >&2; exit 1 ;;
esac
if [ -n "$checksum" ]; then
	printf '%s\n' "$checksum" | grep -Eq '^[0-9a-f]{64}$' || {
		printf 'Unexpected asset digest: %s\n' "$digest" >&2
		exit 1
	}
fi

tempdir=$(mktemp -d)
trap 'rm -r "$tempdir"' EXIT
trap 'exit 1' HUP INT TERM
if [ -z "$checksum" ]; then
	curl -fL --retry 3 -o "$tempdir/osu.AppImage" "https://github.com/ppy/osu/releases/download/${tag}/osu.AppImage"
	checksum=$(sha256sum "$tempdir/osu.AppImage")
	checksum=${checksum%% *}
fi
if [ "$checksum" = "$old_checksum" ]; then
	if [ -n "${GITHUB_OUTPUT:-}" ]; then
		printf 'changed=false\nversion=%s\n' "$old_version" >> "$GITHUB_OUTPUT"
	fi
	exit 0
fi
if [ "$version" = "$old_version" ]; then
	revision=$((old_revision + 1))
else
	revision=1
fi
sed -e "s/^version=.*/version=$version/" \
	-e "s/^revision=.*/revision=$revision/" \
	-e "s/^checksum=.*/checksum=$checksum/" "$template" > "$tempdir/template"
chmod 644 "$tempdir/template"
mv "$tempdir/template" "$template"
if [ -n "${GITHUB_OUTPUT:-}" ]; then
	printf 'changed=true\nversion=%s\n' "$version" >> "$GITHUB_OUTPUT"
fi
printf '%s\n' "$version"

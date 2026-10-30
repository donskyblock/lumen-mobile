#!/usr/bin/env bash
# Downloads the newest SQLite amalgamation from sqlite.org into android-deps/sqlite/, verifying its SHA3-256.
# (sqlite.org publishes no "latest" URL, so the version, URL and hash are read from its download page.)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
DEST="$ROOT/android-deps/sqlite"
mkdir -p "$DEST"
page="$(curl -fsSL https://sqlite.org/download.html)"
row="$(printf '%s\n' "$page" | grep -E '^PRODUCT,[0-9.]+,[0-9]{4}/sqlite-amalgamation-[0-9]+\.zip,' | head -1)"
[ -n "$row" ] || { echo "couldn't find the amalgamation on sqlite.org/download.html"; exit 1; }
IFS=, read -r _ version rel size sha3 <<<"$row"
echo "SQLite $version  ($rel)"
tmp="$(mktemp -d)"
curl -fsSL "https://sqlite.org/$rel" -o "$tmp/sqlite.zip"
got="$(python3 -c "import hashlib,sys; print(hashlib.sha3_256(open(sys.argv[1],'rb').read()).hexdigest())" "$tmp/sqlite.zip")"
[ "$got" = "$sha3" ] || { echo "SHA3-256 mismatch: expected $sha3, got $got"; exit 1; }
unzip -jo "$tmp/sqlite.zip" '*/sqlite3.c' '*/sqlite3.h' -d "$DEST" >/dev/null
echo "$version" > "$DEST/VERSION"
echo "ok: $DEST"

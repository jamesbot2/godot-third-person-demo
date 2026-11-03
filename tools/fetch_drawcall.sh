#!/usr/bin/env bash
# Download the CC0 Quaternius UAL2 "Source" clips redistributed (free, no
# login) by Drawcall Market. Raw zips are NOT committed; the retargeted
# result is assets/animations/ual_clips.res (tools/retarget_drawcall.gd).
#   tools/fetch_drawcall.sh [/workspace/assets_raw]
set -euo pipefail
DST="${1:-/workspace/assets_raw}/drawcall"
mkdir -p "$DST"
# slug@version  sha256 (first 16 hex of the zip we built from)
CLIPS="
safety-vault-root-motion@1.0.4 ce9af6a9907f5e42
climb-ledge@1.0.5 3cdc13d1bbe7cd9e
climb-up-2m-root-motion@1.0.4 aaae5adaf0cc2db7
jog-fwd-loop@1.0.8 d91d6fc24ab79e7a
jog-left-loop@1.0.6 b2ab006663ca1625
jog-right-loop@1.0.6 210fd950c322f9b3
jog-bwd-loop@1.0.6 b6abaa74b66210ac
walk-l-loop@1.0.3 e20c2c0d6b860a30
walk-right-loop@1.0.4 588642c926528b33
walk-bwd-loop@1.0.3 1fbc8f5c9b596786
turn90-l@1.0.5 8ca6cc3204dd0fca
turn90-right@1.0.5 1cd53670a1bef2c1
turn180-left-root-motion-alternate-2@1.0.3 4d75377c9ee5c29e
turn180-r-rm@1.0.3 3dd48984f4e0fede
"
echo "$CLIPS" | while read -r sv sha; do
	[ -z "$sv" ] && continue
	slug="${sv%@*}"
	curl -fsSL "https://market.drawcallcontent.com/zips/${sv}.zip" -o "$DST/$slug.zip"
	got=$(sha256sum "$DST/$slug.zip" | cut -c1-16)
	[ "$got" = "$sha" ] || echo "WARN $slug: sha $got != $sha (upstream re-published?)"
	rm -rf "$DST/$slug" && mkdir -p "$DST/$slug" && (cd "$DST/$slug" && unzip -q "../$slug.zip")
	echo "ok $slug"
done

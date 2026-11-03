#!/bin/bash
# Download a free (pay-what-you-want, $0) Quaternius itch.io pack without a login.
# usage: tools/fetch_quaternius.sh <itch-slug> <out-dir>
#   tools/fetch_quaternius.sh universal-base-characters /workspace/assets_raw/ubc
#   tools/fetch_quaternius.sh universal-animation-library /workspace/assets_raw/ual1
#   tools/fetch_quaternius.sh universal-animation-library-2 /workspace/assets_raw/ual2
# then unzip each pack in place and run tools/build_character_assets.gd.
set -e
G=$1; OUT=$2; mkdir -p $OUT; J=/tmp/itch_cj_$G.txt; rm -f $J
H=$(curl -s -c $J -b $J https://quaternius.itch.io/$G)
CSRF=$(echo "$H" | grep -oE 'name="csrf_token" value="[^"]+"' | head -1 | sed 's/.*value="//;s/"$//')
DU=$(curl -s -c $J -b $J -X POST --data-urlencode "csrf_token=$CSRF" https://quaternius.itch.io/$G/download_url | python3 -c 'import sys,json;print(json.load(sys.stdin)["url"])')
P=$(curl -s -c $J -b $J "$DU")
echo "$P" > $OUT/download_page.html
CSRF2=$(echo "$P" | grep -oE 'name="csrf_token" value="[^"]+"' | head -1 | sed 's/.*value="//;s/"$//')
echo "$P" | grep -oE 'title="[^"]+" class="name"|file_size"><span>[^<]+'
for ID in $(echo "$P" | grep -oE 'data-upload_id="[0-9]+"' | grep -oE '[0-9]+'); do
  NAME=$(echo "$P" | grep -oE "data-upload_id=\"$ID\".{0,400}" | grep -oE 'title="[^"]+" class="name"' | head -1 | sed 's/title="//;s/" class="name"//')
  R=$(curl -s -c $J -b $J -X POST --data-urlencode "csrf_token=$CSRF2" "https://quaternius.itch.io/$G/file/$ID?source=game_download&after_download_lightbox=true")
  URL=$(echo "$R" | python3 -c 'import sys,json;print(json.load(sys.stdin)["url"])')
  echo "downloading $ID '$NAME'"; curl -sL "$URL" -o "$OUT/$NAME"; ls -la "$OUT/$NAME"
done

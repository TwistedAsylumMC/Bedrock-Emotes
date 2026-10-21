#!/bin/bash

set -euo pipefail

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

api() {
    curl -sSfL --retry 3 --retry-all-errors -X POST "https://20ca2.playfabapi.com/$1" \
    -H 'Content-Type: application/json' \
    "${@:2}"
}

LOGINRESULT=$(api Client/LoginWithEmailAddress -d @- <<EOF
{
  "Email": "$EMAIL",
  "Password": "$PASSWORD",
  "TitleId": "20ca2"
}
EOF
)

LOGINENTITYTOKEN=$(echo "$LOGINRESULT" | jq -er '.data.EntityToken.EntityToken')
PLAYFABID=$(echo "$LOGINRESULT" | jq -er '.data.PlayFabId')

ENTITYTOKENRESULT=$(api Authentication/GetEntityToken -H "X-EntityToken: $LOGINENTITYTOKEN" -d @- <<EOF
{
    "Entity": {
        "Id": "$PLAYFABID",
        "Type": "master_player_account"
    }
}
EOF
)

ENTITYTOKEN=$(echo "$ENTITYTOKENRESULT" | jq -er '.data.EntityToken')

TOTALCOUNT=1
SKIP=0
COUNT=300
PAGE=0

fetch_items() {
    local skip=$1
    local count=$2

    ITEMRESULT=$(api Catalog/Search -H "X-EntityToken: $ENTITYTOKEN" -d "{
      \"Filter\": \"(contentType eq 'PersonaDurable' and displayProperties/pieceType eq 'persona_emote')\",
      \"OrderBy\": \"title/neutral asc\",
      \"scid\": \"4fc10100-5f7a-4470-899b-280835760c07\",
      \"skip\": $skip,
      \"top\": $count
    }")

    echo "$ITEMRESULT" | jq -e '[.data.Items[] | {uuid: .DisplayProperties.packIdentity[0].uuid, title: .Title.neutral, author: .DisplayProperties.creatorName, image: .Images[0].Url, rarity: .DisplayProperties.rarity, price: .DisplayProperties.price, created: .CreationDate, offerId: .DisplayProperties.offerId, keywords: .Keywords.neutral.Values}]' > "$TMP/page_$(printf '%05d' $PAGE).json"
    PAGE=$((PAGE + 1))

    if [ $SKIP -eq 0 ]; then
        TOTALCOUNT=$(echo "$ITEMRESULT" | jq -er '.data.Count')
        echo "Total items to fetch: $TOTALCOUNT"
    fi
}

while [ $SKIP -lt $TOTALCOUNT ]; do
    echo "Fetching items $SKIP to $((SKIP + COUNT))"
    fetch_items $SKIP $COUNT
    SKIP=$((SKIP + COUNT))
done

jq -s 'add' "$TMP"/page_*.json > "$TMP/emotes.json"

FETCHED=$(jq 'length' "$TMP/emotes.json")
if [ "$FETCHED" -eq 0 ]; then
    echo "Fetched 0 emotes, refusing to update" >&2
    exit 1
fi
if [ "$FETCHED" -ne "$TOTALCOUNT" ]; then
    echo "Fetched $FETCHED emotes but API reported $TOTALCOUNT, refusing to update" >&2
    exit 1
fi
if [ "$(jq '[.[] | select(.uuid == null or .image == null)] | length' "$TMP/emotes.json")" -ne 0 ]; then
    echo "Some emotes are missing a uuid or image, refusing to update" >&2
    exit 1
fi
if [ -f emotes.json ]; then
    PREVIOUS=$(jq 'length' emotes.json)
    if [ $((FETCHED * 10)) -lt $((PREVIOUS * 9)) ]; then
        echo "Emote count dropped from $PREVIOUS to $FETCHED (>10%), refusing to update" >&2
        exit 1
    fi
fi

mv "$TMP/emotes.json" emotes.json
jq -r '{
  keywords: [.[] | .keywords | select(. != null) | .[]] | unique,
  rarities: [.[] | .rarity] | unique,
  authors: [.[] | .author | select(. != null)] | unique
}' emotes.json > metadata.json

{
    echo "# Bedrock Emotes"
    echo "This repository is scheduled to update every 6 hours automatically. A raw version of the emotes can be found in the [emotes.json](./emotes.json) file. There are currently $FETCHED emotes on the Marketplace."
    jq -r '"| Image | Name | Author | UUID |",
    "|-------|------|--------|------|",
    (.[] | "| <img src=\"./images/\(.uuid).png\" width=\"128\" height=\"128\" /> | \(.title) | \(.author // "") | \(.uuid) |")' emotes.json
} > README.md

jq -r '.[] | [.image, .uuid] | @tsv' emotes.json | while IFS=$'\t' read -r IMAGE UUID; do
    UUID=${UUID%$'\r'}
    if curl -sSfL --retry 3 --retry-all-errors "$IMAGE" -o "$TMP/image.png" && [ -s "$TMP/image.png" ]; then
        mv "$TMP/image.png" "images/$UUID.png"
    else
        echo "Failed to download image for $UUID, keeping existing" >&2
    fi
done

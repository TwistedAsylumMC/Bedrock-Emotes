#!/bin/bash

LOGINRESULT=`curl -s -L -X POST 'https://20ca2.playfabapi.com/Client/LoginWithPlayFab' \
-H 'Content-Type: application/json' \
-d @<(cat <<EOF
{
  "Username": "$USERNAME",
  "Password": "$PASSWORD",
  "TitleId": "20ca2"
}
EOF
)`

LOGINENTITYTOKEN=`echo $LOGINRESULT | jq -r '.data.EntityToken.EntityToken'`
PLAYFABID=`echo $LOGINRESULT | jq -r '.data.PlayFabId'`

ENTITYTOKENRESULT=`curl -s -L -X POST 'https://20ca2.playfabapi.com/Authentication/GetEntityToken' \
-H 'Content-Type: application/json' \
-H "X-EntityToken: $LOGINENTITYTOKEN" \
-d @<(cat <<EOF
{
    "Entity": {
        "Id": "$PLAYFABID",
        "Type": "master_player_account"
    }
}
EOF
)`

ENTITYTOKEN=`echo $ENTITYTOKENRESULT | jq -r '.data.EntityToken'`

ITEMRESULT=`curl -s -L -X POST 'https://20ca2.playfabapi.com/Catalog/SearchItems' \
-H 'Content-Type: application/json' \
-H "X-EntityToken: $ENTITYTOKEN" \
-d '{
  "Filter": "(contentType eq '\''PersonaDurable'\'' and displayProperties/pieceType eq '\''persona_emote'\'')",
  "OrderBy": "title/neutral asc",
  "scid": "4fc10100-5f7a-4470-899b-280835760c07",
  "skip": 0,
  "count": 250
}'`

echo $ITEMRESULT | jq -r '[.data.Items[] | {uuid: .DisplayProperties.packIdentity[0].uuid, title: .Title.neutral, image: .Images[0].Url}]' > emotes.json

echo "# Bedrock Emotes" > README.md
echo "This repository is scheduled to update every 6 hours automatically. A raw version of the emotes can be found in the [emotes.json](./emotes.json) file." >> README.md
cat emotes.json | jq -r '"| Image | Name | UUID |",
"|-------|------|------|",
(.[] | "| <img src=\"./images/\(.uuid).png\" width=\"128\" height=\"128\" /> | \(.title) | \(.uuid) |")' >> README.md

for i in `cat emotes.json | jq -r 'to_entries[] | [.value.image, .value.uuid] | @csv'`
do
  IMAGE=`echo $i | cut -d ',' -f 1 | tr -d '"'`
  UUID=`echo $i | cut -d ',' -f 2 | tr -d '"'`
  wget ${IMAGE} -O images/${UUID}.png
done

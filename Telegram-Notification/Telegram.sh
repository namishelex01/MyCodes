#!/bin/bash

TOKEN=Y0ur:t0k3n-#umb3r
CHAT_ID="-09128374"
URL="https://api.telegram.org/bot$TOKEN/sendMessage"

if [ $# -eq 0 ]
  then
    MESSAGE="You have been notified !!"
else
    MESSAGE=$1
fi

curl -s -X POST $URL -d chat_id=$CHAT_ID -d text="$MESSAGE"

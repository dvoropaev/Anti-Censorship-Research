#!/bin/bash

set -x -e

release_notes_path="$1"
if [ "$release_notes_path" == "" ]; then
  echo "Release notes path not specified"; exit 1
fi

ls -la

jq --arg text "`cat changelog.txt`" '[.["language"]="en-GB" | .["text"]=$text]' <<< '{}' > "$release_notes_path"

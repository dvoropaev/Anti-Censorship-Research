#!/bin/bash

set -x -e

# Moving to a folder with scripts and move to the root directory
cd $(dirname $0)
cd ../..

file_type="$1"
if [[ "$file_type" == "apk" ]] || [[ "$file_type" == "aab" ]]; then
    echo "The file type is correct: ${file_type}"
else
    echo "Unknown file type: ${file_type}."
    mkdir -p "build" && touch "build/app/outputs/flutter-apk/app-release.apk" # Let's create an empty file for Bamboo artifact's publishing
    exit 0
fi

make .dart_tool/build/entrypoint/build.dart

flutter build "$file_type"  \
    --release               \
    -t 'lib/main.dart'      \
    --no-pub

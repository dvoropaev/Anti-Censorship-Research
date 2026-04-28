#!/bin/bash

set -x -e

# Moving to a folder with scripts and move to the root directory
cd $(dirname $0)
cd ../..

git_kit="$1"
if [ "$git_kit" == "" ]; then
  echo "The Git Kit path not specified"; exit 1
fi

"$git_kit" pull "$bamboo_planRepository_repositoryUrl"
bamboo-specs/scripts/increment_version_title.sh "$bamboo_build_channel"
"$git_kit" commit_and_push "pubspec.yaml" "skip ci: Automatic ${bamboo_build_channel} version title increment by Bamboo"

exit $?
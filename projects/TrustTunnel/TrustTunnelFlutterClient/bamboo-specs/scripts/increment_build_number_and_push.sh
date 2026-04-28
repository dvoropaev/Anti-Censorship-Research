#!/bin/bash

set -x -e

# Moving to a folder with scripts and move to the root directory
cd $(dirname $0)
cd ../..

git_kit="$1"
if [ "$git_kit" == "" ]; then
  echo "The Git Kit path not specified"; exit 1
fi

increment_step=0
if [ "$bamboo_repository_branch_name" == "master" ] ; then
  increment_step=100 # Read more about increment steps in the project README file
elif [[ "$bamboo_repository_branch_name" == version/* ]]; then
  increment_step=10 # Read more about increment steps in the project README file 
else
  echo "Let's won't increment the build number on the $bamboo_repository_branch_name branch"; exit 0
fi

"$git_kit" pull "$bamboo_planRepository_repositoryUrl"
bamboo-specs/scripts/increment_build_number.sh $increment_step
"$git_kit" commit_and_push "pubspec.yaml" "skip ci: Automatic build number increment by Bamboo"
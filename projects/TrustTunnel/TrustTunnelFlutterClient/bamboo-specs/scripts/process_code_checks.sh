#!/bin/bash

set -x

directory_to_check="$bamboo_working_directory"
echo "Directory to check: $directory_to_check"

target_branch="$bamboo_planRepository_integrationBranch_branch"
echo "Target branch: $target_branch"

if [[ $target_branch != "master" && $target_branch != "release" && $target_branch != version/* ]]; then
    # We don't check temporary branches
    echo "The target branch is $target_branch. We don't check this branch because it's a temporary branch"
    exit 0
fi

phrase="FIX""ME"

matches=$(grep -rnw "$directory_to_check" -e "$phrase")

if [[ $matches != '' ]]; then
    echo -e "There are $phrase matches in the following files:\n$matches"; exit 1
fi

echo "All code checks passed successfully!"
exit 0

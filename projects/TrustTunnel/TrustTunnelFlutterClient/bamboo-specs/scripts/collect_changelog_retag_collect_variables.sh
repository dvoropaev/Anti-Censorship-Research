#!/bin/bash

set -x

# Moving to a folder with scripts and move to the root directory
cd $(dirname $0)
cd ../..

git_kit="$1"
if [ "$git_kit" == "" ]; then
    echo "The Git Kit path not specified"; exit 1
fi

version_line=$(grep '^version:' pubspec.yaml | head -1 | sed -e "s/version:[ ]*//")

version=$(echo "${version_line}" | cut -d '+' -f 1 | tr -d ' ')
build_number=$(echo "${version_line}" | cut -d '+' -f 2 | tr -d ' ')

echo "Parsed version from pubspec.yaml: ${version}"
echo "Parsed build_number from pubspec.yaml: ${build_number}"

version_with_build_number="${version}.${build_number}"

version_title="${version_with_build_number}"

tag=$(echo "v${version_title}" | sed -e "s/ /-/g" -e "y/ABCDEFGHIJKLMNOPQRSTUVWXYZ/abcdefghijklmnopqrstuvwxyz/")
if [[ "${bamboo_build_channel}" == "release" ]]; then
    tag="${tag}-release"
fi
echo "tag: $tag"

"$git_kit" delete_tag "$tag" "$bamboo_planRepository_repositoryUrl"

bamboo-specs/scripts/collect_changelog.sh "$bamboo_build_channel" "qa_changelog.md" "md" true "$bamboo_customRevision"
qa_changelog_state="Collected successfully"
if grep -q "<html>" qa_changelog.md; then
    echo "The changelog.md file contains an <html> tag. Let's replace it to the 'Minor fixes' phrase."
    qa_changelog_state="Server timeout"
    echo "Minor fixes" > qa_changelog.md
elif [ ! -f qa_changelog.md ]; then
    echo "QA Changelog was not found! Creating a file with 'Minor fixes' phrase..."
    qa_changelog_state="Empty changelog"
    echo "Minor fixes" > qa_changelog.md
fi

bamboo-specs/scripts/collect_changelog.sh "$bamboo_build_channel" "changelog.txt" "txt" false "$bamboo_customRevision"
changelog_state="Collected successfully"
if grep -q "<html>" changelog.txt; then
    echo "The changelog.txt file contains an <html> tag. Let's replace it to the 'Minor fixes' phrase."
    changelog_state="Server timeout"
    echo "Minor fixes" > changelog.txt
elif [ ! -f changelog.txt ]; then
    echo "App Store Changelog was not found! Creating a file with 'Minor fixes' phrase..."
    changelog_state="Empty changelog"
    echo "Minor fixes" > changelog.txt
fi

echo "version_title=${version_title}" > variables.txt
echo "version=${version}" >> variables.txt
echo "build_number=${build_number}" >> variables.txt
echo "version_with_build_number=${version_with_build_number}" >> variables.txt
echo "tag=${tag}" >> variables.txt
echo "qa_changelog_state=${qa_changelog_state}" >> variables.txt
echo "changelog_state=${changelog_state}" >> variables.txt
echo "Variables has been written to the 'variables.txt' file"

"$git_kit" add_tag "${tag}" "HEAD" "${PWD}/variables.txt" "$bamboo_planRepository_repositoryUrl"

exit $?
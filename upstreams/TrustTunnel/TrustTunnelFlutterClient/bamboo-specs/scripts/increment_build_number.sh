#!/bin/bash -x
# The script increments the build number of the application
#   replacing the build number in pubspec.yaml `version:` line.
#
# Params:
#       1, build_number_delta [required]: delta with which to increment a build number version

# Moving to a folder with scripts
cd $(dirname $0)

build_number_delta=$1
if [[ ${build_number_delta} == '' ]]; then
    echo 'Build number delta was not given.'
    exit 1
fi

# Parse the current build number from pubspec.yaml and increment it
version_line=$(cat ../../pubspec.yaml | grep '^version:' | head -1 | sed -e "s/version:[ ]*//")
build_number=$(echo "${version_line}" | cut -d '+' -f 2 | tr -d ' ')
echo "Build number before increment is ${build_number}"
new_build_number=$((build_number+${build_number_delta}))
echo "New build number is ${new_build_number}"

# Split base version and rebuild the version line
base_version=$(echo "${version_line}" | cut -d '+' -f 1)
old_part="version: ${base_version}+${build_number}"
new_part="version: ${base_version}+${new_build_number}"

# Replace build number in pubspec.yaml
sed -i "s/${old_part}/${new_part}/" ../../pubspec.yaml
#!/bin/bash -x
# The script collects a changelog and saves it to the file.
#
# Params:
#       1, channel        [required]: a channel/track/production scope. Can be release, rc, beta, nightly, prenightly
#       2, changelog path [required]: a file path where need to save a changelog
#       3, changelog type [required]: a changelog file type. Can be md, txt, html
#       4, "private" flag [optional]: a flag to be marked whether collect private notes anyway or not
#       5, branch         [optional]: a branch on where log will be collected



collect_private_notes='false'

# Let's get a previous tag
echo "Preparing the changelog"
if [[ "$1" == "" ]] || [[ "$1" == "release" ]]; then
    previous_tag=$(git tag -l "*$1*" --sort -committerdate --sort -taggerdate | head -1)
elif [[ "$1" == "prenightly" ]]; then
    previous_tag=$(git tag -l "*pre-nightly*" --sort -committerdate --sort -taggerdate | head -1)
elif [[ "$1" == "nightly" ]]; then
    previous_tag=$(git tag -l "*pre-nightly*" "*nightly*" --sort -committerdate --sort -taggerdate | head -1)
elif [[ "$1" == "beta" ]]; then
    previous_tag=$(git tag -l "*beta*" "*release*" --sort -committerdate --sort -taggerdate | head -1)
elif [[ "$1" == "rc" ]]; then
    previous_tag=$(git tag -l "*beta*" "*rc*" "*release*" --sort -committerdate --sort -taggerdate | head -1)
else
    echo "Unknown channel: $1"
    exit 1
fi
if  [[ "$previous_tag" == "" ]]; then
    echo "Previous tag is empty, let's get the first commit"
    previous_tag=$(git rev-list --max-parents=0 HEAD)
fi
echo "Previous tag is: ${previous_tag}"

# Let's check whether file name was passed or not
if [[ "$2" == "" ]]; then
    echo "A file name where to put a changelog didn't pass"
    exit 1
fi
filename="$2"
echo "File name to collect a changelog is: $filename"

# Let's check whether a changelog file type was passed or not
if [[ "$3" == "" ]]; then
    echo "A changelog file type has not been passed"
    exit 1
fi
changelog_file_type="$3"
echo "A changelog file type is: $changelog_file_type"

# Let's try to set the 'collect_private_notes' field
if [[ "$4" != "" ]]; then
    echo "The 'collect private notes' value has been passed"
    collect_private_notes="$4"
fi

# Let's check if 'branch' field was passed
current_branch="$5"

if [[ "$current_branch" == "" ]]; then
    echo "No current branch was passed"
fi

# Let's collect a changelog
url="https://jirahub.int.agrd.dev/v1/release_notes/changelog.${changelog_file_type}?repo=ADGUARD-CORE-LIBS/vpn-oss-gui&from_ref=${previous_tag}&private=${collect_private_notes}&branch=${current_branch}"
echo "URL is ${url}"
curl ${url} > "$filename"


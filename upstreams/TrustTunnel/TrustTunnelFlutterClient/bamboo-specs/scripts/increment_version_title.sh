#!/bin/bash -x
# The script increments the version title of the application
#   updating version title counters in pubspec.yaml.
#
# Params:
#       1, build_channel [required]: a build channel to understand what version title is needed to get.



# Moving to a folder with scripts and move to the root directory
cd $(dirname $0)
cd ../..

build_channel=$1
if [[ "$build_channel" == "release" ]]; then resolved_build_channel="Release"
elif [[ "$build_channel" == "rc" ]]; then resolved_build_channel="Rc"
elif [[ "$build_channel" == "beta" ]]; then resolved_build_channel="Beta"
elif [[ "$build_channel" == "nightly" ]]; then resolved_build_channel="Nightly"
elif [[ "$build_channel" == "prenightly" ]]; then resolved_build_channel="PreNightly"
else
    echo "illegal parameter $build_channel. It should be release, rc, beta, nightly or prenightly."
    exit 1
fi
echo "Script will increment version title for $resolved_build_channel build channel"


varName="versionTitle${resolved_build_channel}Number"
number=$(cat pubspec.yaml | grep "${varName}:" | head -1 | sed -e "s/.*: *//" -e "s/[[:space:]]//g")
echo "Current value of ${varName} is ${number}"

if [[ "$number" == "0" ]]; then
    newNumber=1
else
    newNumber=$((number+1))
fi
echo "New value of ${varName} is ${newNumber}"

partBeforeNumber=$(cat pubspec.yaml | grep "${varName}:" | head -1 | sed -e "s/:.*/: /")
oldPart="${partBeforeNumber}${number}"
newPart="${partBeforeNumber}${newNumber}"
sed -i '' "s/$oldPart/$newPart/" pubspec.yaml

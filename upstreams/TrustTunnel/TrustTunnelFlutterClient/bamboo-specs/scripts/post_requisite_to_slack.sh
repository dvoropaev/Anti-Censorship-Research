#!/bin/bash -x

set -x

# Moving to a folder with scripts and move to the root directory
cd $(dirname $0)
cd ../..


#temporary removed [[ "$build_channel" == "rc" ]] || [[ "$build_channel" == "release" ]]
build_channel="$1"
if [[ "$build_channel" == "beta" ]]; then
    echo "The build channel is correct, the posting to slack is allowed"
else
    echo "Unknown build channel: ${build_channel}. The post to slack is not allowed"
    exit 0
fi

slack_kit="$2"
if [ "$slack_kit" == "" ]; then
    echo "The Slack Kit path not specified"; exit 1
fi

# Let's define all necessary variables
slack_channel="#trusttunnel-qa-builds"
uniq_name="TrustTunnel for iOS"
text=`cat <<EOF
_*## ${uniq_name} \\\`[${build_channel}]\\\`*_ :apple-grey:

*Version title:* ${bamboo_data_version_title}
*Tag:* ${bamboo_data_tag}
*Tech version (for Deck):* ${bamboo_data_version_with_build_number}
*Artifacts:* <https://bamboo.int.agrd.dev/browse/${bamboo_planKey}-${bamboo_buildNumber}/artifact|link>

*Changelog state:* ${bamboo_data_changelog_state}
*QA Changelog state:* ${bamboo_data_qa_changelog_state}
EOF`
changelog=$(cat "changelog.txt")

# Let's count how many lines the changelog contains
lines_count=$(echo "$changelog" | wc -l)
need_send_changelog=false

if [ $lines_count -le 30 ]; then
    if [ "$changelog" == '' ]; then
        text="${text}

\`There is no public changelog (for Deck, Github, Testflight, etc.).\`"
    else
        text="${text}

*Public changelog (for Deck, Github, Testflight, etc.):*
\`\`\`${changelog}\`\`\`"
    fi
else
    need_send_changelog=true
fi

python3 "$slack_kit" -f "TrustTunnel.app.zip" -m "$text" -fn "TrustTunnel.app.zip" -c "$slack_channel" -pin -unpin "${uniq_name}" "${build_channel}"
if [ $? -eq 1 ]; then
    exit 1
fi
if [ $need_send_changelog == true ]; then
    python3 "$slack_kit" -f "changelog.txt" -m "Public changelog (for Deck, Github, Testflight, etc.)" -c "$slack_channel"
    exit $?
fi
python3 "$slack_kit" -f "qa_changelog.md" -m "Changelog for QA team" -c "$slack_channel"

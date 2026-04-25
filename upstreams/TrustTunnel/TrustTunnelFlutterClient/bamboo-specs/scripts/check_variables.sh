#!/bin/bash

set -x

if [[ "${bamboo_customRevision}" == "" ]]; then
    echo "Error: custom revision is not set but it should be."
    exit 1
fi

if [[ "${bamboo_build_channel}" != "prenightly" ]] && [[ "${bamboo_build_channel}" != "nightly" ]] && [[ "${bamboo_build_channel}" != "beta" ]] && [[ "${bamboo_build_channel}" != "rc" ]] && [[ "${bamboo_build_channel}" != "release" ]]; then
    echo "Error: incorrect build channel: ${bamboo_build_channel}. Can be prenightly/nightly/beta/rc/release."
    exit 1
fi

if [[ "${bamboo_postToSlack}" != "true" ]] && [[ "${bamboo_postToSlack}" != "false" ]]; then
  echo "Error: incorrect 'post to slack' value: ${bamboo_postToSlack}. Can be true/false"
  exit 1
fi

exit 0

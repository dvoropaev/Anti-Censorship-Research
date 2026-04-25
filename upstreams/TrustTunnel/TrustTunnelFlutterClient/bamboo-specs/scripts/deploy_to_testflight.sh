#!/bin/bash

set -x

project_dir="$1"
if [[ "${project_dir}" == "" ]]; then
  echo "The project directory path not specified"; exit 1
fi

submit_beta_review="$2"
if [[ "${submit_beta_review}" == "" ]]; then
  submit_beta_review="false"
fi 

# Moving to a folder with scripts and move to the root directory
cd $(dirname $0)
cd ../..


changelog_path="${PWD}/changelog.txt"
if grep -q "<html>" "${changelog_path}"; then
    echo "The changelog.txt file contains an <html> tag. Let's replace it to the 'Minor fixes' phrase."
    echo "Minor fixes" > "${changelog_path}"
fi


changelog_text=$(cat "${changelog_path}")
echo "Welcome to TrustTunnel ${bamboo_data_version_title}!" > changelog.txt
echo "" >> "${changelog_path}"
echo "" >> "${changelog_path}"
echo "## Release notes" >> "${changelog_path}"
echo "" >> "${changelog_path}"
echo "$changelog_text" >> "${changelog_path}"



echo "${bamboo_fastlaneAppStoreApiInfoSecret}" | base64 --decode > "${project_dir}/ios/fastlane/AppStoreApiInfo.json"
echo "${bamboo_fastlaneEnvSecret}" | base64 --decode > "${project_dir}/ios/fastlane/.env"

cd ios
# Configure bundler
bundle config set --local path '.bundle/vendor'
bundle install
if [ $? -eq 1 ]; then exit 1; fi



bundle exec fastlane deploy_to_testflight changelog_path:"${changelog_path}" track:"$bamboo_build_channel" distribute_external:"$bamboo_distribute_external" submit_beta_review:"$submit_beta_review"

exit $?

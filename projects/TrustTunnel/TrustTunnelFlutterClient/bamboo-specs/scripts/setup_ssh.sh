#!/bin/sh

set -x -e

# Should be called once per job that needs SSH
printf "%b\n" "${bamboo_sshSecretKey}" | ssh-add -

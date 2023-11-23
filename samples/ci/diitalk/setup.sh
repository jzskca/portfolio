#!/bin/sh
# This script performs the run-time actions necessary to prepare the environment for running tests.
set -eu

ci/git.sh init

# Prepare reports directory
mkdir test-reports

# Log in to the Amazon ECR repository
$(aws ecr get-login --no-include-email --region us-west-2)

docker_info=$(docker info)
if echo "$docker_info" | grep -q userns; then
    echo Setting cache permissions for user namespace remapping
    root_uid=$(echo "$docker_info" | grep 'Docker Root Dir' | cut -d/ -f5 | cut -d. -f1)
    www_data_uid=$(expr "$root_uid" + 33)
    echo root UID is "$root_uid"
    echo www-data UID is "$www_data_uid"
else
    echo Setting cache permissions for host user namespace
    root_uid=0
    www_data_uid=33
fi

# Set cache permissions
chown -R "$www_data_uid":"$www_data_uid" .composer
chown -R "$root_uid":"$root_uid" .npm

# Import Docker cache
ci/docker.sh import_cache

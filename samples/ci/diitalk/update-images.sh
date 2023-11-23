#!/bin/bash
set -eu

# Checks for image updates. Returns true if images need to be updated, false otherwise.
images_updated() {
    registry_domain=8675309.dkr.ecr.us-west-2.amazonaws.com
    changed=0
    token=$(jq -r '.auths["'$registry_domain'"].auth' ~/.docker/config.json)

    # Check for any new or changed images.
    #
    # Ignore images tagged with this revision. There will always be another tag for the same image (e.g. prod, 1.2.3),
    # so if no changes are detected here, then we've simply added new tags and no new images. We'll push them below if
    # necessary.
    #
    # Note that process substitution (`<()` syntax) is used instead of a pipe to feed the `while` loop because pipes are
    # run in subshells, and that would cause the value of $changed to be lost.
    echo Checking for image updates...
    start=$(date +%s)
    while read -r image; do
        repository=$(cut -d: -f1 <<<"$image")
        tag=$(cut -d: -f2 <<<"$image")
        local_id=$(docker images --format '{{.ID}}' --no-trunc "$image")
        url=https://$(cut -d/ -f1 <<<"$repository")/v2/$(cut -d/ -f2- <<<"$repository")/manifests/$tag
        remote_id=$(curl -fs -H "Authorization: Basic $token" "$url" | jq -r .config.digest)

        if [[ $local_id != "$remote_id" ]]; then
            echo Image "$repository":"$tag" has changed
            changed=$((changed + 1))
        fi
    done < <(cd docker-images && cat .*.images | grep -ve -"$(cat .revision)"'$' | sort)
    echo Image checks completed in $(($(date +%s) - start))s

    # No new images, therefore no need to update references or caches
    if [[ $changed -eq 0 ]]; then
        echo No image changes
        return 1
    fi

    return 0
}

# This script is only meant for the develop branch. Refuse to update images and caches for other branches.
if [ "$BITBUCKET_BRANCH" != develop ]; then
    echo Not updating images and caches for branch "$BITBUCKET_BRANCH"
    exit 0
fi

# Make docker images
# Note that this will update image references (see docker-images/Makefile.common). Images are always built to ensure
# that the prod images which include the current code are up to date.
(cd docker-images && make)

# Check for image updates. If nothing has changed, then we don't need to push images or update caches.
images_updated || exit 0

# Push images. Do this in the background so that we can update the docker cache in parallel.
(cd docker-images && make release) &
push_pid=$!

# Export Docker cache
ci/docker.sh export_cache

# Wait for the pushes to complete
wait $push_pid

# Commit and push image reference changes once images have been pushed successfully
ci/git.sh commit_image_updates

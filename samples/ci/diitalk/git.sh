#!/bin/sh
set -eu

init() {
    # The merge machinery complains without the next two lines
    git config user.name Pipelines
    git config user.email pipelines@diitalk.com

    # Retrieve and merge in develop
    git fetch origin develop:refs/remotes/origin/develop
    git merge -m 'merge develop' origin/develop

    # Initialize submodules
    git submodule update --init
}

commit_image_updates() {
    # Configuration for pushing back to the repository
    access_token=$(curl -s -X POST -u "$CLIENT_ID:$CLIENT_SECRET" \
        https://bitbucket.org/site/oauth2/access_token \
        -d grant_type=client_credentials -d scopes=repository | jq --raw-output .access_token)
    git remote set-url origin \
        https://x-token-auth:"$access_token"@bitbucket.org/"$BITBUCKET_REPO_OWNER"/"$BITBUCKET_REPO_SLUG"

    if [ "$(git status --porcelain | wc -l)" -gt 0 ]; then
        # Commit and push, making sure to NOT run Pipelines on the new commit
        git commit -am '[skip ci] Automatic image updates'
        git push
    else
        echo No changes to commit
    fi
}

case $1 in
    init | commit_image_updates) $1 ;;
    *) echo Invalid operation && exit 1 ;;
esac

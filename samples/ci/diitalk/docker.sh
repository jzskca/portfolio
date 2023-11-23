#!/bin/sh
set -eu

url=s3://diitalk-internal/pipelines/docker_cache.tar.gz
local=/tmp/docker_cache.tar.gz
description='Docker cache'
registry_domain=8675309.dkr.ecr.us-west-2.amazonaws.com

import_cache() {
    echo Downloading "$description"...
    aws s3 cp --quiet $url $local
    echo Importing "$description"...
    docker load <$local
}

export_cache() {
    new=$local.new
    echo Saving "$description"...

    # Remove all unreferenced and obsolete images
    (cd docker-images && make docker-clean)

    # Display list of images we're saving
    filter=reference="$registry_domain/*/*"
    docker images --filter "$filter"

    # Generate archive
    #
    # `docker history -q` seems to be necessary to get all of the intermediate images; see:
    #   https://github.com/moby/moby/issues/20380#issuecomment-245762498
    #
    # `gzip -1` is used because the space savings do not warrant the time taken for any additional compression. For an
    # archive of 3671841792 bytes:
    #
    #   compression:         1       2       3       4       5       6       7       8       9
    #   time (s):           49      58      60      63      77     106     128     234     358
    #   ratio:          39.72%  38.99%  38.39%  37.28%  36.58%  36.27%  36.18%  36.07%  36.04%
    #   savings (MiB):       0   25.69   46.58   85.43  110.06  120.76  124.15  127.83  128.83
    images=$(docker images --filter "$filter" --format '{{.Repository}}:{{.Tag}}' | sort)
    docker save "$images" "$(for i in $images; do docker history -q "$i"; done | sort | uniq | grep -v '<missing>')" |
        gzip -1n >$new

    if cmp --quiet $new $local; then
        echo No changes to "$description"
    else
        echo Uploading "$description"...
        aws s3 cp --quiet $new $url
    fi
}

case $1 in
    import_cache | export_cache) $1 ;;
    *) echo Invalid operation && exit 1 ;;
esac

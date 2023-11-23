#!/bin/sh
set -eu

# Generate the list of changed files
# We only care about changes introduced by the non-develop branch, as those introduced by develop should already be
# signed off. Worst case scenario, we would waste time rebuilding images already built on develop, if changes on develop
# had resulted in image changes.
list=$(mktemp)
range=origin/develop...HEAD
if [ "$(git rev-parse --abbrev-ref HEAD)" = develop ]; then
    range=HEAD^..HEAD
fi
git diff --name-only $range >"$list"

# docker-images
# This must be done before any other tests, as they may rely on the new images
# We do NOT push the images here; that's done in the release script
if grep -q ^docker-images "$list"; then
    cd docker-images
    make
    cd -
fi

cd docker-compose/test

DOCKER_COMPOSE='docker-compose -f docker-compose.yml -f ../../docker-compose.pipelines.yml'

# admin
if grep -q ^admin "$list"; then
    $DOCKER_COMPOSE run --rm admin
fi

# bats
if grep -qE '\.(sh|bats)$' "$list"; then
    $DOCKER_COMPOSE run --rm bats
fi

# logstashconf
if grep -q ^logstash-conf "$list"; then
    $DOCKER_COMPOSE run --rm logstashconf
fi

# mongooseim
if grep -q ^mongooseim "$list"; then
    (cd ../../docker-images && make mongooseim)
fi

# phpunit
if grep -qE '^(logstash-conf|website)' "$list"; then
    $DOCKER_COMPOSE run --rm phpunit --log-junit /test-reports/junit.xml
fi

# push-daemon
if grep -qE ^push-daemon "$list"; then
    $DOCKER_COMPOSE run --rm push-daemon
fi

# rabbitmq
if grep -qE ^docker-images/rabbitmq/config/definitions.json.tmpl "$list"; then
    definitions_file=../../docker-images/rabbitmq/config/definitions.json.tmpl
    $DOCKER_COMPOSE up -d rabbitmq
    $DOCKER_COMPOSE exec -T rabbitmq /tools/wait-for-it.sh -t 0 localhost:15672
    $DOCKER_COMPOSE exec -T rabbitmq curl -fSs -u guest:guest \
        http://localhost:15672/api/definitions |
        ../develop/format-rabbitmq-definitions.py >$definitions_file
    git diff --exit-code -- $definitions_file
fi

# sms-sender
if grep -q ^sms-sender "$list"; then
    $DOCKER_COMPOSE run --rm sms-sender
fi

# updatescripts
if grep -qE '^website/modules/dingaling/(migrations|sql)/' "$list"; then
    $DOCKER_COMPOSE run --rm updatescripts
fi

rm "$list"

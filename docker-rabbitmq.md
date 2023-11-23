---
theme: solarized_dark.json
---

# Practical example: RabbitMQ

- Dependencies: `base` → `erlang`, `gpg-fetcher`
- Utilize `dockerize` to build configuration files in entrypoint
  - All environments share same configuration files
  - Files use go templates
    - Interpolate environment variables
    - Selectively include/exclude sections depending on target environment
- Separate development/test and production images

---

## Dockerfile

```dockerfile
# RabbitMQ image
#
# This image includes:
# - Management plugin
# - Kubernetes discovery plugin (prod image)
# - Queue, exchange, and user definitions
# - Constant cookie value for clustering
#
# The following environment variables are required:
# - RABBITMQ_PASSWORD_EVENTS: Password for "events" user
# - RABBITMQ_PASSWORD_FREESWITCH: Password for "freeswitch" user
# - RABBITMQ_PASSWORD_LOGSTASH: Password for "logstash" user
# - RABBITMQ_PASSWORD_MONGOOSEIM: Password for "mongooseim" user


#
# Builder stage
#

FROM 8675309.dkr.ecr.us-west-2.amazonaws.com/project/gpg-fetcher AS builder

# Fetch repository GPG key
RUN curl -fsSL https://packagecloud.io/rabbitmq/rabbitmq-server/gpgkey > /tmp/gpg.asc && \
    gpg --import /tmp/gpg.asc && \
    gpg --export F6609E60DC62814E > /tmp/gpg
```

---

## Dockerfile

```dockerfile
#
# Base stage
#

FROM 8675309.dkr.ecr.us-west-2.amazonaws.com/project/erlang:base AS base

# Install repository GPG key
COPY --from=builder /tmp/gpg /etc/apt/trusted.gpg.d/rabbitmq.gpg

# Using packagecloud because only the latest version is available in RabbitMQ's main repository
# XXX The distro is stretch because no packages are built for buster. The package is not installable on stretch,
# however, because its version of erlang is too old.
RUN echo deb https://packagecloud.io/rabbitmq/rabbitmq-server/debian/ stretch main \
        > /etc/apt/sources.list.d/rabbitmq.list

# Install RabbitMQ
RUN export DEBIAN_FRONTEND=noninteractive && \
    apt-get update && \
    apt-get install -y \
        rabbitmq-server=3.7.9-1 \
        && \
    find /var/lib/apt/lists/ -type f -delete

# Set a constant cookie
RUN COOKIEFILE=/var/lib/rabbitmq/.erlang.cookie && \
    echo rabbitmq > $COOKIEFILE && \
    chown rabbitmq:rabbitmq $COOKIEFILE && \
    chmod 600 $COOKIEFILE
```

---

## Dockerfile

```dockerfile
# Copy files
COPY config/ /etc/rabbitmq/
COPY entrypoint.sh /usr/local/bin/

# Log to stdout
ENV RABBITMQ_LOGS=- \
    RABBITMQ_SASL_LOGS=-

# Open AMQP (plain and TLS), management plugin, and inter-node/CLI communication port
EXPOSE 5671 5672 15672 25672

CMD ["entrypoint.sh"]


#
# Prod stage
#

FROM base AS prod

# Enable the k8s discovery plugin
RUN rabbitmq-plugins enable --offline rabbitmq_peer_discovery_k8s
```

---

## Entrypoint

```bash
#!/bin/bash
set -eu

find /etc/rabbitmq -name '*.tmpl' | while read -r f; do
    /usr/local/bin/dockerize -template "$f":"${f//\.tmpl$/}"
done

exec su-exec rabbitmq /usr/lib/rabbitmq/bin/rabbitmq-server
```

---

## Config

### `definitions.json.tmpl`

```json
{
  "bindings": [
    {
      "arguments": {},
      "destination": "analytics",
      "destination_type": "queue",
      "routing_key": "10",
      "source": "analytics",
      "vhost": "/"
    }
  ],
  "exchanges": [
    {
      "arguments": { "hash-header": "x-hash-header" },
      "auto_delete": false,
      "durable": true,
      "internal": false,
      "name": "analytics",
      "type": "x-consistent-hash",
      "vhost": "/"
    }
  ],
  "permissions": [
    {
      "configure": "",
      "read": "",
      "user": "analytics",
      "vhost": "/",
      "write": "^analytics"
    }
  ]
}
```

---

## Config

### `definitions.json.tmpl`

```json
{
  "queues": [
    {
      "arguments": {},
      "auto_delete": false,
      "durable": true,
      "name": "analytics",
      "vhost": "/"
    }
  ],
  "users": [
    {
      "hashing_algorithm": "rabbit_password_hashing_sha256",
      "name": "analytics",
      "password_hash": "{{.Env.RABBITMQ_PASSWORD_ANALYTICS}}",
      "tags": ""
    }
  ],
  "vhosts": [
    {
      "name": "/"
    }
  ]
}
```

---

## Config

### `enabled_plugins`

```erlang
[rabbitmq_consistent_hash_exchange,rabbitmq_management].
```

---

## Config

### `rabbitmq.conf.tmpl`

```
# Load queue/exchange/user definitions
management.load_definitions = /etc/rabbitmq/definitions.json

{{if .Env.K8S_SERVICE_NAME}}
    # Clustering
    cluster_formation.k8s.address_type = hostname
    cluster_formation.k8s.host = kubernetes.default.svc.cluster.local
    cluster_formation.k8s.hostname_suffix = .rabbitmq.default.svc.cluster.local
    cluster_formation.k8s.service_name = rabbitmq
    cluster_formation.node_cleanup.interval = 60
    cluster_formation.node_cleanup.only_log_warning = false
    cluster_formation.peer_discovery_backend = rabbit_peer_discovery_k8s
    cluster_partition_handling = autoheal

    # Reduce startup delay when using StatefulSets
    cluster_formation.randomized_startup_delay_range.min = 0
    cluster_formation.randomized_startup_delay_range.max = 1

    # Queue master locator
    queue_master_locator = min-masters
{{end}}
```

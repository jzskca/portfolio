---
theme: solarized_dark.json
---

# Renewing TLS certificates

## Problem

- Update staging and production certificates across multiple services and pods
- HTTPS also necessary on dev:
  - Consistentcy with staging/prod
  - Certain services require it (e.g. WebRTC)
- Solutions such as custom CAs require manual intervention, which is especially impractical on mobile

## Solution

- Use Let's Encrypt + `certbot` to renew certificates automatically
- Use `cron` for dev, `CronJob` for staging/prod
- Reload processes once certificate renewed
- Zero-downtime updates

---

## Dev

- Which authentication challenge to use?
  - HTTP-01 not feasible as container may not be publicly accessible
  - DNS-01 is feasible since container already uses a shared development AWS key
  - Shared development key has limited permissions: can only modify records in the `dev.project.com` zone
- `cron` job installed during bootstrapping attempts renewal daily
- Certificate state stored in persistent volume

---

### `docker-compose`

```bash
version: "2"
  web:
    command: compose-entrypoint.sh
    depends_on:
      - db
      - redis
    environment:
      AWS_ACCESS_KEY_ID: AKIAXXXXXXXXXXXXXXXX
      AWS_SECRET_ACCESS_KEY: 0000000000000000000000000000000000000000
      VHOST: $VHOST
      WWW_SERVER_ALIASES: $VHOST
      WWW_SERVER_ALIASES_TLS: $VHOST
      WWW_SERVER_NAME: www.$VHOST
    image: 8675309.dkr.ecr.us-west-2.amazonaws.com/project/apache:dev-6ebba489
    networks:
      default:
        aliases:
          - $VHOST
          - www-int
    ports:
      - 80
      - 443
    volumes:
      - ../../docker-images/apache/config/sites-enabled/project.conf.tmpl:/etc/apache2/sites-enabled/project.conf.tmpl:ro
      - ../../website:/srv/www/project:ro
      - ./web/allow-extra.conf:/etc/apache2/conf-enabled/allow-extra.conf:ro
      - ./web/compose-entrypoint.sh:/usr/local/bin/compose-entrypoint.sh:ro
      - ./web/composer-install.sh:/usr/local/bin/composer-install.sh:ro
      - ./web/dev.conf:/etc/apache2/conf-enabled/dev.conf:ro
      - certificate:/cert/:ro
volumes:
  certificate:
```

---

### `update-certificate.sh`

```bash
# Create/update the certificate
# - Copy live files to volume root (avoids permissions issues under archive/)
# - Create fullbundle.pem (used by Mongooseim)
# - `true` used in --deploy-hook because it needs a command under $PATH (`cd` is built in to the shell)
docker run \
    --rm \
    -v "${COMPOSE_PROJECT_NAME}"_certificate:/etc/letsencrypt/ \
    -e AWS_ACCESS_KEY_ID="$AWS_ACCESS_KEY_ID" \
    -e AWS_SECRET_ACCESS_KEY="$AWS_SECRET_ACCESS_KEY" \
    certbot/dns-route53 certonly \
    --non-interactive \
    $quiet \
    --cert-name "$COMPOSE_PROJECT_NAME" \
    --agree-tos \
    --email "$user"@project.com \
    --dns-route53 \
    -d\ {www.,}$VHOST \
    --deploy-hook " \
        true && \
        cd /etc/letsencrypt/ && \
        cp -aL live/$COMPOSE_PROJECT_NAME/* . && \
        cat cert.pem chain.pem privkey.pem > fullbundle.pem \
    "
```

---

### `cron` job

```bash
add_cron_job () {
    crontab -l | grep -qFx "$1" && return
    (crontab -l; echo "$1") | crontab -
}

add_cron_job "17 11 * * * $PWD/develop/update-certificate.sh --quiet"
```

---

## Staging/Production

- Which authentication challenge to use?
  - DNS-01 seems reasonable, but Route 53 permission granualarity is entire zone
  - HTTP-01 is feasible, except that we can't control which pod receives the request
    - Shared storage could be used, but that restricts pods to a single AZ
  - Use HTTP-01 with Redis as an intermediary
    - `certbot` saves challenge in Redis, `.well-known` endpoint returns value
    - `certbot-redis-plugin` patched to require a prefix so endpoint can restrict keys returned
- `CronJob` attempts renewal daily
- Certificate state stored in persistent volume

---

### `Dockerfile`

```dockerfile
FROM debian:buster-20191118-slim AS builder

RUN export DEBIAN_FRONTEND=noninteractive && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        python3-setuptools \
        unzip \
        && \
    find /var/lib/apt/lists -type f -delete

RUN curl -LO https://storage.googleapis.com/kubernetes-release/release/v1.12.10/bin/linux/amd64/kubectl && \
    chmod a+x kubectl && \
    mv kubectl /usr/local/bin/

# chgrp is a workaround for https://github.com/moby/moby/issues/34645
RUN cd /tmp && \
    curl -LO https://github.com/project/certbot-redis-plugin/archive/master.zip && \
    unzip *.zip && \
    cd certbot-redis-plugin-* && \
    python3 setup.py install && \
    chgrp -R root /usr/local/lib/python* && \
    cd /tmp && \
    rm -rf *.zip certbot-redis-plugin-*
```

---

### `Dockerfile`

```dockerfile
FROM debian:buster-20200224-slim AS base

RUN export DEBIAN_FRONTEND=noninteractive && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        python3-setuptools \
        && \
    find /var/lib/apt/lists -type f -delete

COPY --from=builder /usr/local/bin/kubectl /usr/local/bin/
COPY --from=builder /usr/local/bin/certbot /usr/local/bin/
COPY --from=builder /usr/local/lib/python3.7/ /usr/local/lib/python3.7/

ADD update-certificate.sh /usr/local/bin/
ADD update-certificate.lib.sh /usr/local/lib/

ENTRYPOINT ["update-certificate.sh"]
```

---

### `update-certificate.lib.sh`

```bash
cert_name=www-certificate

kubectl() {
    command kubectl \
        --certificate-authority=/run/secrets/kubernetes.io/serviceaccount/ca.crt \
        --namespace="$(cat /run/secrets/kubernetes.io/serviceaccount/namespace)" \
        --token="$(cat /run/secrets/kubernetes.io/serviceaccount/token)" \
        --server="https://$KUBERNETES_SERVICE_HOST:$KUBERNETES_SERVICE_PORT"
}

update_secret() {
    certdir=/etc/letsencrypt/live/$cert_name
    kubectl patch secret $cert_name -p "{
        \"data\": {
            \"cert.pem\": \"$(base64 -w0 $certdir/cert.pem)\",
            \"fullbundle.pem\": \"$(cat $certdir/fullchain.pem $certdir/privkey.pem | base64 -w0)\",
            \"fullchain.pem\": \"$(base64 -w0 $certdir/fullchain.pem)\",
            \"privkey.pem\": \"$(base64 -w0 $certdir/privkey.pem)\"
        }
    }"
}

update_pods() {
    for pod in $(kubectl get pods -l app=www -o name); do
        kubectl exec "$(basename "$pod")" -- service apache2 reload
    done
    for pod in $(kubectl get pods -l app=mongooseim -o name); do
        kubectl exec "$(basename "$pod")" -- /usr/local/mongooseim/bin/mongooseimctl restart
    done
}
```

---

### `update-certificate.sh`

```bash
# [1] suggests a maximum default wait of 2 minutes before Secret changes are propagated to pods. We will wait 2.5
# minutes to provide a small buffer. Some relevant kubelet configuration values for our current (1.12) EKS clusters:
#
#   * configMapAndSecretChangeDetectionStrategy: Cache
#   * syncFrequency: 1min
#
#   [1] https://kubernetes.io/docs/tasks/configure-pod-container/configure-pod-configmap/#mounted-configmaps-are-…
#   [2] https://kubernetes.io/docs/concepts/configuration/secret/#using-secrets-as-files-from-a-pod
#
# Notes:
# - The Redis server URL is constant thanks to the redis Service
# - The Redis prefix is the leading path (i.e. the key is the full path under the domain)
# - The domain list is built from values in the environment-config ConfigMap ($WWW_SERVER_ALIASES_TLS is optional)
# - `true` is used because --deploy-hook wants the first argument to be an executable in $PATH
certbot certonly \
    --non-interactive \
    --quiet \
    --agree-tos \
    --email admin@project.com \
    --cert-name $cert_name \
    -a certbot-redis:redis \
    --certbot-redis:redis-redis-url=redis://redis:6379 \
    --certbot-redis:redis-redis-prefix=.well-known/acme-challenge/ \
    -d $WWW_SERVER_NAME${WWW_SERVER_ALIASES_TLS:+,$WWW_SERVER_ALIASES_TLS} \
    --deploy-hook 'true && . /usr/local/lib/update-certificate.lib.sh && update_secret && sleep 150 && update_pods'
```

---

### `CronJob`

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: certificate-updater
```

---

### `CronJob`

```yaml
kind: Role
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: certificate-updater
rules:
  - apiGroups: [""]
    resources: ["pods"]
    verbs: ["get", "list"]
  - apiGroups: [""]
    resources: ["pods/exec"]
    verbs: ["create"]
  - apiGroups: [""]
    resources: ["secrets"]
    resourceNames: ["www-certificate"]
    verbs: ["get", "patch"]
```

---

### `CronJob`

```yaml
kind: RoleBinding
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: certificate-updater
subjects:
  - kind: ServiceAccount
    name: certificate-updater
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: certificate-updater
```

---

### `CronJob`

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: certificate-updater-state
spec:
  accessModes: ["ReadWriteOnce"]
  resources:
    requests:
      storage: 1Gi
```

---

### `CronJob`

```yaml
apiVersion: batch/v1beta1
kind: CronJob
metadata:
  name: certificate-updater
spec:
  schedule: "47 19 * * *"
  concurrencyPolicy: Replace
  jobTemplate:
    spec:
      template:
        spec:
          serviceAccountName: certificate-updater
          restartPolicy: Never
          containers:
            - name: certificate-updater
              image: 8675309.dkr.ecr.us-west-2.amazonaws.com/project/certificate-updater:base-6ebba489
              envFrom:
                - configMapRef:
                    name: environment-config
              volumeMounts:
                - name: certificate-updater-state
                  mountPath: /etc/letsencrypt
          volumes:
            - name: certificate-updater-state
              persistentVolumeClaim:
                claimName: certificate-updater-state
```

---

### `WellKnown` Controller

```php
<?php
/**
 * Controller to serve `/.well-known` files from Redis.
 *
 * This is intended for ACME http-01 certificate validation, which verifies that an entity requesting an X.509
 * certificate owns the domain it is claiming by being able to provision a file under a known path
 * (`/.well-known/acme-challenge/`). Since the process which makes this request does not run on our web server, we use
 * Redis to mediate the exchange.
 *
 * To ensure that arbitrary keys can not be fetched from Redis, we use the full path as the key, and verify that it
 * begins with `.well-known/`.
 */
class Controller_WellKnown extends Controller
{
    const PREFIX = '.well-known/';

    public function action_index()
    {
        $key = $this->request->uri();
        if (substr($key, 0, strlen(self::PREFIX)) != self::PREFIX || !preg_match('#^[\w/._-]+$#', $key)) {
            throw new HTTP_Exception_404();
        }

        $result = RedisClient::getInstance()->get($key);
        if (empty($result)) {
            throw new HTTP_Exception_404();
        }

        $this->response->headers('Content-Type', 'text/plain');
        $this->response->body($result);
    }
}
```

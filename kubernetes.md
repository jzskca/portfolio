---
theme: solarized_dark.json
---

# Kubernetes

## Layout

- `base`: basic configuration applied to all projects and environments.
- `overlays`: project- and environment-specific configuration.
- Other optional components are defined under directories at this level.

## Usage

```sh
# View configuration
kubectl kustomize kubernetes/overlays/$project/$environment

# Deploy
kubectl apply -k kubernetes/overlays/$project/$environment
```

---

## Tree

```
 kubernetes
├──  base
│   ├──  backend.yaml
│   ├──  celery.yaml
│   ├──  frontend.yaml
│   └──  kustomization.yaml
├──  extra1
│   ├──  extra1.yaml
│   └──  kustomization.yaml
└──  overlays
    ├──  project1
    │   ├──  production
    │   │   ├──  backend-environment.env
    │   │   ├──  backend-secrets.yaml
    │   │   ├──  extra1-environment.env
    │   │   ├──  ingress.yaml
    │   │   └──  kustomization.yaml
    │   └──  staging
    │       ├──  backend-environment.env
    │       ├──  backend-secrets.yaml
    │       ├──  extra1-environment.env
    │       ├──  ingress.yaml
    │       └──  kustomization.yaml
    └──  project2
        ├──  production
        │   ├──  backend-environment.env
        │   ├──  backend-secrets.yaml
        │   ├──  ingress.yaml
        │   └──  kustomization.yaml
        └──  staging
            ├──  backend-environment.env
            ├──  backend-secrets.yaml
            ├──  ingress.yaml
            └──  kustomization.yaml
```

---

## `base/backend.yaml`

### Service

```yaml
apiVersion: v1
kind: Service
metadata:
  name: backend
  labels:
    app: backend
    tier: backend
  annotations:
    alb.ingress.kubernetes.io/healthcheck-path: /health/
spec:
  ports:
    - port: 80
      name: http
  selector:
    app: backend
    tier: backend
```

---

## `base/backend.yaml`

### Deployment

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: backend
spec:
  selector:
    matchLabels:
      app: backend
      tier: backend
  replicas: 1
  template:
    metadata:
      labels:
        app: backend
        tier: backend
    spec:
      containers:
        - name: www
          image: __BACKEND__
          ports:
            - containerPort: 80
          resources:
            limits:
              cpu: 2
              memory: 1024Mi
            requests:
              cpu: 0.25
              memory: 128Mi
          envFrom:
            - configMapRef:
                name: backend-environment
            - secretRef:
                name: backend-secrets
```

---

## `base/backend.yaml`

### HorizontalPodAutoscaler

```yaml
apiVersion: autoscaling/v2beta2
kind: HorizontalPodAutoscaler
metadata:
  name: backend
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: backend
  minReplicas: 1
  maxReplicas: 10
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 60
```

---

## `base/kustomization.yaml`

```yaml
resources:
  - backend.yaml
  - celery.yaml
  - frontend.yaml
```

---

## `overlays/project1/staging/backend-environment.env`

```env
ALLOWED_CIDR_NETS=10.0.0.0/16
ALLOWED_HOSTS=staging.project1.com,localhost
AWS_ACCESS_KEY_ID=AKYYYYYYYYYYYYYYYYYY
AWS_DEFAULT_REGION=ca-central-1
CELERY_BROKER_URL=redis://project1-staging.abc123.ng.0001.cac1.cache.amazonaws.com:6379
DATABASE_HOST=project1-staging.cluster-abc123.ca-central-1.rds.amazonaws.com
DATABASE_HOST_RO=project1-staging.cluster-ro-abc123.ca-central-1.rds.amazonaws.com
DATABASE_NAME=project1-staging
DATABASE_USER=project1-staging
DJANGO_SETTINGS_MODULE=config.settings
ENVIRONMENT=staging
FIREBASE_CONFIG={"databaseURL": "https://project1-staging-abc123.firebaseio.com/"}
FRONTEND_URL=https://staging.project1.ca
LANGUAGES=en-CA:English
O365_CLIENT_ID=11111111-2222-4333-8444-555555555555
O365_TENANT_ID=99999999-8888-4777-a666-555555555555
PAYPAL_CLIENT_ID=ABC456
PAYPAL_WEBHOOK_ID=ZXY654
PHONENUMBER_DEFAULT_REGION=CA
REDIS_URL=redis://project1-staging.abc123.ng.0001.cac1.cache.amazonaws.com:6379
SENTRY_DSN=https://0123456789@o9876.ingest.sentry.io/01234
SLACK_EVENTS_CHANNEL_ID=C98765
SUPPORT_FROM_EMAIL_ADDRESS=support@project1.com
```

---

## `overlays/project1/production/backend-environment.env`

```env
ALLOWED_CIDR_NETS=10.1.0.0/16
ALLOWED_HOSTS=www.project1.com,localhost
AWS_ACCESS_KEY_ID=AKZZZZZZZZZZZZZZZZZZ
AWS_DEFAULT_REGION=ca-central-1
CELERY_BROKER_URL=redis://project1.abc123.ng.0001.cac1.cache.amazonaws.com:6379
DATABASE_HOST=project1.cluster-abc123.ca-central-1.rds.amazonaws.com
DATABASE_HOST_RO=project1.cluster-ro-abc123.ca-central-1.rds.amazonaws.com
DATABASE_NAME=project1
DATABASE_USER=project1
DJANGO_SETTINGS_MODULE=config.settings
ENVIRONMENT=production
FIREBASE_CONFIG={"databaseURL": "https://project1-abc123.firebaseio.com/"}
FRONTEND_URL=https://www.project1.ca
LANGUAGES=en-CA:English
O365_CLIENT_ID=11111111-2222-4333-8444-555555555555
O365_TENANT_ID=99999999-8888-4777-a666-555555555555
PAYPAL_CLIENT_ID=ABC123
PAYPAL_WEBHOOK_ID=ZXY987
PHONENUMBER_DEFAULT_REGION=CA
REDIS_URL=redis://project1.abc123.ng.0001.cac1.cache.amazonaws.com:6379
SENTRY_DSN=https://0123456789@o9876.ingest.sentry.io/01234
SLACK_EVENTS_CHANNEL_ID=C98765
SUPPORT_FROM_EMAIL_ADDRESS=support@project1.com
```

---

## `overlays/project1/staging/backend-secrets.yaml`

```yaml
apiVersion: bitnami.com/v1alpha1
kind: SealedSecret
metadata:
  creationTimestamp: null
  name: backend-secrets
  namespace: default
spec:
  encryptedData:
    AWS_SECRET_ACCESS_KEY: AgCafuOm4S4LF/Qu1e…
    DATABASE_PASSWORD: AgBgC8O0REhydKO76u…
    DJANGO_SECRET_KEY: AgCEa9e8WyABC21NpS…
    FIREBASE_CREDENTIALS: AgB2OEwwrcdn5jr7GD…
    O365_CLIENT_SECRET: AgBKpN9Hi7qdgSG6vO…
    PAYPAL_CLIENT_SECRET: AgCRMqWNLLjO9OY5mB…
  template:
    data: null
    metadata:
      creationTimestamp: null
      name: backend-secrets
      namespace: default
```

---

## `overlays/project1/staging/ingress.yaml`

### Preamble

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: www
  annotations:
    alb.ingress.kubernetes.io/actions.canonical-domain-redirect: >
      {
        "Type": "redirect",
        "RedirectConfig": {
          "Protocol": "HTTPS",
          "Host": "staging.project1.com",
          "Port": "443",
          "Path": "/#{path}",
          "Query": "#{query}",
          "StatusCode": "HTTP_301"
        }
      }
    alb.ingress.kubernetes.io/ip-address-type: dualstack
    alb.ingress.kubernetes.io/listen-ports: '[{"HTTP": 80}, {"HTTPS":443}]'
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/ssl-policy: ELBSecurityPolicy-FS-1-2-Res-2020-10
    alb.ingress.kubernetes.io/ssl-redirect: "443"
    alb.ingress.kubernetes.io/target-type: ip
spec:
  ingressClassName: alb
  tls:
    - hosts:
        - staging.project1.com
```

---

## `overlays/project1/staging/ingress.yaml`

### Rules (canonical)

```yaml
rules:
  - host: staging.project1.com
    http:
      paths:
        # Backend services
        - path: /graphql/
          pathType: Prefix
          backend:
            service:
              name: backend
              port:
                name: http
        - path: /paypal/
          pathType: Prefix
          backend:
            service:
              name: backend
              port:
                name: http

        # Frontend services
        - path: /
          pathType: Prefix
          backend:
            service:
              name: frontend
              port:
                name: http
```

---

## `overlays/project1/staging/ingress.yaml`

### Rules (non-canonical)

```yaml
rules:
  - http:
      paths:
        # Canonical domain redirect
        - path: /
          pathType: Prefix
          backend:
            service:
              name: canonical-domain-redirect
              port:
                name: use-annotation
```

---

## `kubernetes/overlays/project1/staging/kustomization.yaml`

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - backend-secrets.yaml
  - ingress.yaml
  - ../../../base/
  - ../../../extra1/
configMapGenerator:
  - name: backend-environment
    envs:
      - backend-environment.env
  - name: extra1-environment
    envs:
      - extra1-environment.env
images:
  - name: __BACKEND__
    newName: 8675309.dkr.ecr.ca-central-1.amazonaws.com/project1/backend
    newTag: 01234567
  - name: __CELERY_BEAT__
    newName: 8675309.dkr.ecr.ca-central-1.amazonaws.com/project1/backend
    newTag: celery-beat-01234567
  - name: __CELERY_WORKER__
    newName: 8675309.dkr.ecr.ca-central-1.amazonaws.com/project1/backend
    newTag: celery-worker-01234567
  - name: __FRONTEND__
    newName: 8675309.dkr.ecr.ca-central-1.amazonaws.com/project1/frontend
    newTag: 01234567
```

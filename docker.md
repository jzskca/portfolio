---
theme: solarized_dark.json
---

# Multi-stage Docker builds

- `base`: common denominator
- `builder`: artifact build stage
- Remainder are target images, built atop `base`, copying in artifacts from `builder`

```
~~~graph-easy --as=boxart
graph { flow: east; }
[ base ] --> { start: front,0; } [ image A ], [ image B ], [ image C ], [ builder ]
[ image A ] --> { start: east; end: west; } [ image A1 ], [ image A2 ]
[ builder ] ..> { flow: south; } [ image A ], [ image B ]
~~~
```

---

## `base`

```dockerfile
FROM python:3.9.10 AS base

RUN export DEBIAN_FRONTEND=noninteractive && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        postgresql-client \
        && \
    find /var/lib/apt/lists/ -type f -delete
```

---

## `builder`

```dockerfile
FROM base AS builder

RUN export DEBIAN_FRONTEND=noninteractive && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        gettext \
        && \
    find /var/lib/apt/lists/ -type f -delete

COPY requirements /requirements
RUN cd /requirements && \
    pip install pip-tools==6.3.0 && \
    pip-sync --pip-args '--no-cache' && \
    # https://github.com/moby/moby/issues/34645
    chown -R root:root /usr/local/lib/python3.9/

COPY . /srv/django/
RUN cd /srv/django && django-admin compilemessages
```

---

## `backend-common`

```dockerfile
FROM base AS backend-common

COPY --from=builder /usr/local/lib/python3.9/ /usr/local/lib/python3.9/
COPY --from=builder /srv/django/ /srv/django/

ENV PYTHONPATH=/srv/django
WORKDIR /srv/django
```

---

## `backend`

```dockerfile
FROM backend-common as backend

COPY --from=builder /usr/local/bin/django-admin /usr/local/bin/django-admin
COPY --from=builder /usr/local/bin/hypercorn /usr/local/bin/hypercorn

EXPOSE 80

ENTRYPOINT ["hypercorn"]
CMD ["--access-logfile", "-", "--error-logfile", "-", "--bind", "0.0.0.0:80", "config.asgi:application"]
```

---

## `chime-event-listener`

```dockerfile
FROM backend-common AS chime-event-listener

USER nobody
ENTRYPOINT ["python3"]
CMD ["./manage.py", "chime_event_listener"]
```

---

## `celery-worker`

```dockerfile
FROM backend-common AS celery-worker

COPY --from=builder /usr/local/bin/celery /usr/local/bin/celery

USER nobody
ENTRYPOINT ["celery", "-A", "config"]
CMD ["worker"]
```

---

## `celery-beat`

```dockerfile
FROM celery-worker AS celery-beat

CMD ["beat", "-s", "/tmp/celerybeat-schedule"]
```

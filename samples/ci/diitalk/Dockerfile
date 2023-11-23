FROM debian:buster-20200224-slim AS base

# Install packages
RUN export DEBIAN_FRONTEND=noninteractive && \
    apt-get update && \
    apt-get install --no-install-recommends -y \
        ca-certificates \
        curl \
        git \
        jq \
        make \
        python3 \
        && \
    find /var/lib/apt/lists/ -type f -delete && \
    find /usr -name __pycache__ | xargs rm -rf


FROM base AS builder

RUN export DEBIAN_FRONTEND=noninteractive && \
    apt-get update && \
    apt-get install --no-install-recommends -y \
        python3-pip \
        python3-setuptools \
        && \
    find /var/lib/apt/lists/ -type f -delete

# Install awscli
# pip does not perform true dependency resolution, nor does it error out when
# incompatibilities are detected. We therefore perform our own check and abort
# if conflicts are found.
# https://github.com/pypa/pip/issues/988
RUN pip3 install --no-cache-dir --no-compile \
        awscli \
        # Manual conflict resolution
        'urllib3<1.25,>=1.21.1' \
        'PyYAML<4.3,>=3.10' \
        # Redirection for conflict checks below
        2>&1 | tee /tmp/pip.out && \
    ! grep incompatible /tmp/pip.out && \
    rm /tmp/pip.out && \
    find /usr -name __pycache__ | xargs rm -rf && \
    # Workaround for https://github.com/moby/moby/issues/34645
    chgrp -R root /usr/local/lib/python3.7


FROM base AS prod

# Install awscli
COPY --from=builder /usr/local/bin/aws /usr/local/bin/
COPY --from=builder /usr/local/lib/python3.7/ /usr/local/lib/python3.7/

# Install docker-compose
RUN url=https://github.com/docker/compose/releases/download/1.24.1/docker-compose-Linux-x86_64 && \
    file=/usr/local/bin/docker-compose && \
    curl -fsSL -o $file $url && \
    chmod a+x $file

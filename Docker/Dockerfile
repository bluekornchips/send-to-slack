# CI image that installs from the locally mounted repo.
FROM alpine:3.20

RUN apk add --no-cache \
        bash \
        ca-certificates \
        curl \
        gettext \
        git \
        gzip \
        jq \
        tar

# Use bash for RUN steps so "source" works and pipefail is available.
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

WORKDIR /tmp/send-to-slack
COPY . /tmp/send-to-slack

RUN set -euo pipefail; \
        source /tmp/send-to-slack/bin/install.sh; \
        perform_installation /tmp/send-to-slack /usr/local; \
        rm -rf /tmp/send-to-slack

CMD ["/bin/bash"]
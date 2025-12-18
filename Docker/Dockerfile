# CI image that bundles the locally mounted repo.
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
        install -d -m 755 /usr/local/send-to-slack/lib/blocks /usr/local/bin; \
        install -m 755 /tmp/send-to-slack/bin/send-to-slack.sh /usr/local/send-to-slack/send-to-slack; \
        install -m 755 /tmp/send-to-slack/lib/*.sh /usr/local/send-to-slack/lib/; \
        install -m 755 /tmp/send-to-slack/lib/blocks/*.sh /usr/local/send-to-slack/lib/blocks/; \
        install -m 644 /tmp/send-to-slack/VERSION /usr/local/send-to-slack/VERSION; \
        ln -sf /usr/local/send-to-slack/send-to-slack /usr/local/bin/send-to-slack; \
        rm -rf /tmp/send-to-slack

CMD ["/bin/bash"]
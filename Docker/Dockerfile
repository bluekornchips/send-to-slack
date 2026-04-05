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
        install -d -m 755 /usr/local/send-to-slack/lib/slack/utils /usr/local/send-to-slack/lib/slack/block-kit/blocks /usr/local/send-to-slack/lib/parse /usr/local/bin; \
        install -m 755 /tmp/send-to-slack/bin/send-to-slack.sh /usr/local/send-to-slack/send-to-slack; \
        install -m 755 /tmp/send-to-slack/lib/metadata.sh /usr/local/send-to-slack/lib/; \
        install -m 755 /tmp/send-to-slack/lib/parse/*.sh /usr/local/send-to-slack/lib/parse/; \
        install -m 755 /tmp/send-to-slack/lib/slack/api.sh /tmp/send-to-slack/lib/slack/crosspost.sh /tmp/send-to-slack/lib/slack/replies.sh /usr/local/send-to-slack/lib/slack/; \
        install -m 755 /tmp/send-to-slack/lib/slack/utils/*.sh /usr/local/send-to-slack/lib/slack/utils/; \
        install -m 755 /tmp/send-to-slack/lib/slack/block-kit/create-block.sh /usr/local/send-to-slack/lib/slack/block-kit/; \
        install -m 755 /tmp/send-to-slack/lib/slack/block-kit/blocks/*.sh /usr/local/send-to-slack/lib/slack/block-kit/blocks/; \
        install -m 644 /tmp/send-to-slack/VERSION /usr/local/send-to-slack/VERSION; \
        ln -sf /usr/local/send-to-slack/send-to-slack /usr/local/bin/send-to-slack; \
        rm -rf /tmp/send-to-slack

CMD ["/bin/bash"]
FROM --platform=amd64 alpine:3.20

RUN apk add --no-cache bash jq curl ca-certificates && \
	addgroup -g 1000 slack && \
	adduser -D -u 1000 -G slack -h /opt/resource slack

WORKDIR /opt/resource

COPY --chown=slack:slack ./concourse/resource-type/scripts/check.sh /opt/resource/check
COPY --chown=slack:slack ./concourse/resource-type/scripts/in.sh /opt/resource/in
COPY --chown=slack:slack ./concourse/resource-type/scripts/out.sh /opt/resource/out
COPY --chown=slack:slack ./send-to-slack.sh /opt/resource/send-to-slack.sh
COPY --chown=slack:slack ./bin/ /opt/resource/bin/

RUN chmod +x /opt/resource/check /opt/resource/in /opt/resource/out /opt/resource/send-to-slack.sh /opt/resource/bin/*

ENV SEND_TO_SLACK_ROOT=/opt/resource

USER slack

ENTRYPOINT ["/bin/bash"]
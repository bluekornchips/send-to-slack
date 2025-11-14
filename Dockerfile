FROM --platform=amd64 alpine:3.20

RUN apk add --no-cache \
	bash \
	jq \
	curl \
	ca-certificates

RUN addgroup -g 1000 slack && \
	adduser -D -u 1000 -G slack -h /opt/resource slack

COPY --chown=slack:slack ./concourse/resource-type/scripts/check.sh /opt/resource/check
COPY --chown=slack:slack ./concourse/resource-type/scripts/in.sh /opt/resource/in
COPY --chown=slack:slack ./concourse/resource-type/scripts/out.sh /opt/resource/out
COPY --chown=slack:slack ./send-to-slack.sh /opt/resource/send-to-slack.sh
COPY --chown=slack:slack ./bin/ /opt/resource/bin/

RUN find /opt/resource -type f -name "*.sh" -exec chmod +x {} \; && \
	chmod -R 755 /opt/resource

WORKDIR /opt/resource

ENV SEND_TO_SLACK_ROOT=/opt/resource

USER slack

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
	CMD bash -c 'test -f /opt/resource/send-to-slack.sh' || exit 1

ENTRYPOINT ["/bin/bash"]
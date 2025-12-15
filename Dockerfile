FROM --platform=amd64 alpine:3.20

RUN apk add --no-cache bash jq curl ca-certificates gettext && \
	mkdir -p /opt/resource

WORKDIR /opt/resource

COPY ./concourse/resource-type/scripts/check.sh /opt/resource/check
COPY ./concourse/resource-type/scripts/in.sh /opt/resource/in
COPY ./concourse/resource-type/scripts/out.sh /opt/resource/out

COPY ./bin/send-to-slack.sh /opt/resource/send-to-slack
COPY ./lib/ /opt/resource/lib/
COPY ./VERSION /opt/resource/VERSION

ENV SEND_TO_SLACK_ROOT=/opt/resource
ENV PATH=$PATH:/opt/resource

RUN chmod +x /opt/resource/send-to-slack && \
	chmod +x /opt/resource/lib/*.sh && \
	chmod +x /opt/resource/lib/blocks/*.sh

ENTRYPOINT ["/bin/bash"]
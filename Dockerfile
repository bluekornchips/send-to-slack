FROM --platform=amd64 alpine:3.20

RUN apk add --no-cache bash jq curl ca-certificates gettext

WORKDIR /opt/resource

COPY ./concourse/resource-type/scripts/check.sh /opt/resource/check
COPY ./concourse/resource-type/scripts/in.sh /opt/resource/in
COPY ./concourse/resource-type/scripts/out.sh /opt/resource/out
COPY ./send-to-slack.sh /opt/resource/send-to-slack.sh
COPY ./bin/ /opt/resource/bin/

RUN chmod +x /opt/resource/check /opt/resource/in /opt/resource/out /opt/resource/send-to-slack.sh /opt/resource/bin/*

ENV SEND_TO_SLACK_ROOT=/opt/resource

ENTRYPOINT ["/bin/bash"]
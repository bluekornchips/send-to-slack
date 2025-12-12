FROM --platform=amd64 alpine:3.20

RUN apk add --no-cache bash jq curl ca-certificates gettext \
	&& addgroup -S slacker \
	&& adduser -S -G slacker -h /home/slacker -s /bin/bash slacker \
	&& chmod 700 /home/slacker \
	&& chmod 1777 /tmp \
	&& mkdir -p /opt/resource

WORKDIR /opt/resource

COPY ./concourse/resource-type/scripts/check.sh /opt/resource/check
COPY ./concourse/resource-type/scripts/in.sh /opt/resource/in
COPY ./concourse/resource-type/scripts/out.sh /opt/resource/out
COPY ./send-to-slack.sh /opt/resource/send-to-slack.sh
COPY ./bin/ /opt/resource/bin/

RUN chown -R slacker:slacker /opt/resource /home/slacker \
	&& chmod -R u+rwX,g-rwx,o-rwx /opt/resource /home/slacker

ENV SEND_TO_SLACK_ROOT=/opt/resource

USER slacker

ENTRYPOINT ["/bin/bash"]
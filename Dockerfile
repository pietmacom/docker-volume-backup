FROM alpine:latest

ENV DOCKER_SOCK=/var/run/docker.sock

RUN apk update && \
	apk add docker-cli gpg openssh-client curl rsync

COPY ./src/*.sh /root/
RUN chmod ugo+x /root/*.sh

WORKDIR /root
CMD [ "/root/entrypoint.sh" ]
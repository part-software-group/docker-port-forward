FROM docker.loc:5000/alpine:3.7

RUN apk --no-cache add socat

CMD ["socat"]
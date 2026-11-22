FROM alpine:3.22

RUN apk add --no-cache samba-server samba-common-tools avahi tini shadow tzdata \
 && rm -f /etc/avahi/services/*.service \
 && mkdir -p /backups

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENV TM_USER=timemachine \
    TM_SHARE_NAME=TimeMachine \
    TM_SIZE_LIMIT=1T \
    TM_HOSTNAME=timemachine \
    PUID=1000 \
    PGID=1000 \
    ENABLE_AVAHI=1

VOLUME ["/backups"]
EXPOSE 445

HEALTHCHECK --interval=60s --timeout=5s --start-period=20s \
  CMD nc -z 127.0.0.1 445 || exit 1

ENTRYPOINT ["/sbin/tini", "--", "/entrypoint.sh"]

# Backup diário dos Postgres da VPS, com cópia externa criptografada (rclone crypt).
# Detalhes em backup.sh e no README ("Backup").
FROM alpine:3.20

RUN apk add --no-cache docker-cli postgresql16-client rclone tzdata

COPY backup.sh /usr/local/bin/backup.sh
COPY crontab /etc/crontabs/root
RUN chmod +x /usr/local/bin/backup.sh

CMD ["crond", "-f", "-l", "8"]

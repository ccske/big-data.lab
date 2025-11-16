FROM mysql:8

COPY mysql/etc/mysql/conf.d/* /etc/mysql/conf.d/
COPY mysql/docker-entrypoint-initdb.d/* /docker-entrypoint-initdb.d/
RUN chmod +x /docker-entrypoint-initdb.d/*.sh || true

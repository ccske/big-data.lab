FROM mysql:8

COPY etc/mysql/conf.d/* /etc/mysql/conf.d/
COPY docker-entrypoint-initdb.d/* /docker-entrypoint-initdb.d/
RUN chmod +x /docker-entrypoint-initdb.d/*.sh || true

FROM mysql:8

COPY mysql/etc/mysql/conf.d/my.cnf /etc/mysql/conf.d/
COPY mysql/docker-entrypoint-initdb.d/*.sql /docker-entrypoint-initdb.d/

FROM big-data.lab/hadoop

ENV HIVE_HOME=/opt/hive
ENV HIVE_CONF_DIR=${HIVE_HOME}/conf
ENV HIVE_LOG_DIR=/var/log/hive
ENV HIVE_PID_DIR=/var/run/hive
ENV HIVESERVER2_PID_DIR=${HIVE_PID_DIR}

ARG HIVE_VERSION=4.0.1
RUN set -eux && \
    curl -fkSL "https://archive.apache.org/dist/hive/hive-${HIVE_VERSION}/apache-hive-${HIVE_VERSION}-bin.tar.gz" | tar -xz -C /opt && \
    ln -s apache-hive-${HIVE_VERSION}-bin ${HIVE_HOME}

ARG MYSQL_CONNECTOR_J_VERSION=8.4.0
RUN set -eux && \
    curl -fkSL "https://downloads.mysql.com/archives/get/p/3/file/mysql-connector-j-${MYSQL_CONNECTOR_J_VERSION}.tar.gz" | tar -xz -C /tmp && \
    cp -f /tmp/mysql-connector-j-${MYSQL_CONNECTOR_J_VERSION}/mysql-connector-j-${MYSQL_CONNECTOR_J_VERSION}.jar ${HIVE_HOME}/lib/ && \
    rm -rf /tmp/mysql-connector-j-${MYSQL_CONNECTOR_J_VERSION}

RUN set -eux && \
    mkdir -p ${HIVE_LOG_DIR} ${HIVE_PID_DIR} && \
    chgrp supergroup ${HIVE_LOG_DIR} ${HIVE_PID_DIR} && \
    chmod -R 775 ${HIVE_LOG_DIR} ${HIVE_PID_DIR}

COPY hive/conf/* ${HIVE_CONF_DIR}/
COPY hive/entrypoint/entrypoint-*.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/entrypoint-*.sh

ENV JAVA_TOOL_OPTIONS="--add-opens=java.base/java.net=ALL-UNNAMED --add-opens=java.base/java.lang=ALL-UNNAMED --add-opens=java.base/java.nio=ALL-UNNAMED"
RUN rm -f ${HADOOP_HOME}/share/hadoop/common/lib/slf4j-reload4j-*.jar

ENTRYPOINT ["/usr/bin/tini", "--"]

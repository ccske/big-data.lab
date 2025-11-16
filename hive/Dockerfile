FROM big-data.lab/base:latest

ENV HADOOP_CONF_DIR=${HADOOP_HOME}/etc/hadoop
ENV HIVE_CONF_DIR=${HIVE_HOME}/conf
ENV HIVE_LOG_DIR=/var/log/hive
ENV HIVE_PID_DIR=/var/run/hive
ENV HIVESERVER2_PID_DIR=${HIVE_PID_DIR}

RUN set -eux && \
    mkdir -p ${HIVE_LOG_DIR} ${HIVE_PID_DIR} && \
    chgrp supergroup ${HIVE_LOG_DIR} ${HIVE_PID_DIR} && \
    chmod -R 775 ${HIVE_LOG_DIR} ${HIVE_PID_DIR}

COPY hadoop/etc/hadoop/* ${HADOOP_CONF_DIR}/
COPY hive/conf/* ${HIVE_CONF_DIR}/
COPY hive/entrypoint/* /usr/local/bin/
RUN chmod +x /usr/local/bin/entrypoint-*.sh

ENV JAVA_TOOL_OPTIONS="--add-opens=java.base/java.net=ALL-UNNAMED --add-opens=java.base/java.lang=ALL-UNNAMED --add-opens=java.base/java.nio=ALL-UNNAMED"
RUN rm -f ${HADOOP_HOME}/share/hadoop/common/lib/slf4j-reload4j-*.jar

ENTRYPOINT ["/usr/bin/tini", "--"]

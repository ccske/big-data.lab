FROM big-data.lab/base:latest

ENV HADOOP_CONF_DIR=${HADOOP_HOME}/etc/hadoop
ENV HADOOP_LOG_DIR=/var/log/hadoop
ENV HADOOP_VAR_DIR=/var/hadoop
ENV HADOOP_PID_DIR=${HADOOP_VAR_DIR}/pid
ENV HADOOP_TMP_DIR=${HADOOP_VAR_DIR}/tmp
ENV PATH=${HADOOP_HOME}/bin:${HADOOP_HOME}/sbin:$PATH

RUN set -eux && \
    mkdir -p ${HADOOP_PID_DIR} ${HADOOP_TMP_DIR} /volumes/data /volumes/logs && \
    chgrp supergroup ${HADOOP_PID_DIR} ${HADOOP_TMP_DIR} /volumes/data /volumes/logs && \
    chmod -R 775 ${HADOOP_PID_DIR} ${HADOOP_TMP_DIR} /volumes/data /volumes/logs && \
    ln -s /volumes/data ${HADOOP_TMP_DIR}/dfs && \
    ln -s /volumes/logs ${HADOOP_LOG_DIR}

COPY etc/hadoop/* ${HADOOP_HOME}/etc/hadoop/
COPY entrypoint/* /usr/local/bin/
RUN chmod +x /usr/local/bin/entrypoint-*.sh

ENTRYPOINT ["/usr/bin/tini", "--"]

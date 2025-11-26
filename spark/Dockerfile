FROM big-data.lab/hadoop

ARG SPARK_VERSION
ENV SPARK_HOME=/opt/spark
ENV SPARK_CONF_DIR=${SPARK_HOME}/conf
ENV SPARK_LOG_DIR=/var/log/spark

ARG SPARK_TGZ="spark-${SPARK_VERSION}-bin-hadoop3.tgz"
COPY package/${SPARK_TGZ} /tmp/
RUN set -eux && \
    tar -xzf /tmp/${SPARK_TGZ} -C /opt && \
    chown -R root:root /opt/spark-${SPARK_VERSION}-bin-hadoop3 && \
    ln -s spark-${SPARK_VERSION}-bin-hadoop3 ${SPARK_HOME} && \
    rm -f /tmp/${SPARK_TGZ}

RUN set -eux && \
    useradd -G supergroup -r -M spark

RUN set -eux && \
    ln -s /volumes/logs ${SPARK_LOG_DIR}

COPY spark/conf/* ${SPARK_CONF_DIR}/
RUN set -eux && \
    find "${SPARK_CONF_DIR}" -type f -print0 | xargs -0 sed -i "s/HADOOP_MASTER/${HADOOP_MASTER}/g"

COPY spark/entrypoint/entrypoint-*.sh /entrypoint/
RUN set -eux && \
    chmod +x /entrypoint/entrypoint-*.sh

ENTRYPOINT ["/usr/bin/tini","--"]

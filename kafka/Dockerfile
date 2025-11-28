FROM ubuntu:24.04

RUN set -eux && \
    userdel -f -r ubuntu

ARG DEBIAN_FRONTEND=noninteractive
RUN apt-get update && \
    apt-get upgrade -y && \
    apt-get install -y --no-install-recommends gosu netcat-openbsd openjdk-11-jdk-headless procps tini && \
    rm -rf /var/lib/apt/lists/*

ARG KAFKA_VERSION
ARG SCALA_VERSION
ENV KAFKA_HOME=/opt/kafka
ENV KAFKA_CONF_DIR=${KAFKA_HOME}/config
ENV KAFKA_DATA_DIR=/var/kafka/data
ENV KAFKA_LOG_DIR=/var/log/kafka
ENV LOG_DIR=${KAFKA_LOG_DIR}

ARG KAFKA_TGZ="kafka_${SCALA_VERSION}-${KAFKA_VERSION}.tgz"
COPY tarball/${KAFKA_TGZ} /tmp/
RUN set -eux && \
    tar -xzf /tmp/${KAFKA_TGZ} -C /opt && \
    chown -R root:root /opt/kafka_${SCALA_VERSION}-${KAFKA_VERSION} && \
    ln -s kafka_${SCALA_VERSION}-${KAFKA_VERSION} ${KAFKA_HOME} && \
    rm -f /tmp/${KAFKA_TGZ}

RUN set -eux && \
    groupadd -r supergroup && \
    useradd -G supergroup -r -M hdfs && \
    useradd -G supergroup -r -M yarn && \
    useradd -G supergroup -r -M mapred && \
    useradd -G supergroup -r -M spark && \
    useradd -G supergroup -r -M kafka

RUN set -eux && \
    mkdir -p ${KAFKA_DATA_DIR} ${KAFKA_LOG_DIR} && \
    chgrp supergroup ${KAFKA_DATA_DIR} ${KAFKA_LOG_DIR} && \
    chmod 775 ${KAFKA_DATA_DIR} ${KAFKA_LOG_DIR}

ARG KAFKA_HOSTNAME
COPY kafka/config/kraft/* ${KAFKA_CONF_DIR}/kraft/
RUN set -eux && \
    find "${KAFKA_CONF_DIR}/kraft" -type f -print0 | xargs -0 sed -i "s/KAFKA_HOSTNAME/${KAFKA_HOSTNAME}/g"

COPY lib/common.sh kafka/entrypoint/entrypoint.sh /entrypoint/
RUN set -eux && \
    chmod +x /entrypoint/entrypoint.sh

ENTRYPOINT ["/usr/bin/tini", "--"]

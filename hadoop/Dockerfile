FROM ubuntu:24.04

RUN set -eux && userdel -f -r ubuntu

ARG DEBIAN_FRONTEND=noninteractive
RUN apt-get update && \
    apt-get upgrade -y && \
    apt-get install -y --no-install-recommends curl netcat-openbsd openjdk-11-jdk-headless procps gosu tini && \
    rm -rf /var/lib/apt/lists/*

ARG HADOOP_VERSION=3.4.0
ENV HADOOP_HOME=/opt/hadoop
ENV HADOOP_CONF_DIR=${HADOOP_HOME}/etc/hadoop
ENV HADOOP_LOG_DIR=/var/log/hadoop
ENV HADOOP_PID_DIR=/var/run/hadoop
ENV HADOOP_TMP_DIR=/var/hadoop/tmp

ARG TARGETARCH
RUN set -eux && \
    case "${TARGETARCH:-unknown}" in \
      amd64)  HADOOP_TGZ="hadoop-${HADOOP_VERSION}.tar.gz" ;; \
      arm64)  HADOOP_TGZ="hadoop-${HADOOP_VERSION}-aarch64.tar.gz" ;; \
      *)      echo "Unsupported arch: ${TARGETARCH}"; exit 1 ;; \
    esac && \
    curl -fkSL "https://archive.apache.org/dist/hadoop/common/hadoop-${HADOOP_VERSION}/${HADOOP_TGZ}" | tar -xz -C /opt && \
    ln -s hadoop-${HADOOP_VERSION} ${HADOOP_HOME}

RUN set -eux && \
    groupadd -r supergroup && \
    useradd -G supergroup -r -M hdfs && \
    useradd -G supergroup -r -M yarn && \
    useradd -G supergroup -r -M mapred

RUN set -eux && \
    mkdir -p ${HADOOP_PID_DIR} ${HADOOP_TMP_DIR} /volumes/data /volumes/logs && \
    chgrp supergroup ${HADOOP_PID_DIR} ${HADOOP_TMP_DIR} /volumes/data /volumes/logs && \
    chmod -R 775 ${HADOOP_PID_DIR} ${HADOOP_TMP_DIR} /volumes/data /volumes/logs && \
    ln -s /volumes/data ${HADOOP_TMP_DIR}/dfs && \
    ln -s /volumes/logs ${HADOOP_LOG_DIR}

ARG HADOOP_MASTER
ENV HADOOP_MASTER=${HADOOP_MASTER}
COPY hadoop/etc/hadoop/* ${HADOOP_HOME}/etc/hadoop/
RUN set -eux && \
    find "${HADOOP_HOME}/etc/hadoop/" -type f -print0 | xargs -0 sed -i "s/HADOOP_MASTER/${HADOOP_MASTER}/g"

COPY lib/common.sh hadoop/entrypoint/entrypoint-*.sh /entrypoint/
RUN set -eux && \
    chmod +x /entrypoint/entrypoint-*.sh

ENTRYPOINT ["/usr/bin/tini", "--"]

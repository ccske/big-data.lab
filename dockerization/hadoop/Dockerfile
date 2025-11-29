FROM ubuntu:24.04

RUN set -eux && \
    userdel -f -r ubuntu

ARG DEBIAN_FRONTEND=noninteractive
RUN apt-get update && \
    apt-get upgrade -y && \
    apt-get install -y --no-install-recommends gosu netcat-openbsd openjdk-11-jdk-headless procps python3 tini && \
    rm -rf /var/lib/apt/lists/*

ARG TARGETARCH
ARG HADOOP_VERSION
ENV HADOOP_HOME=/opt/hadoop
ENV HADOOP_CONF_DIR=${HADOOP_HOME}/etc/hadoop
ENV HADOOP_TMP_DIR=/var/hadoop/tmp
ENV HADOOP_LOG_DIR=/var/log/hadoop
ENV HADOOP_PID_DIR=/var/run/hadoop

COPY tarball/hadoop-${HADOOP_VERSION}*.tar.gz /tmp/
RUN set -eux && \
    case "${TARGETARCH:-unknown}" in \
      amd64)  HADOOP_TGZ="hadoop-${HADOOP_VERSION}.tar.gz" ;; \
      arm64)  HADOOP_TGZ="hadoop-${HADOOP_VERSION}-aarch64.tar.gz" ;; \
      *)      echo "Unsupported arch: ${TARGETARCH}"; exit 1 ;; \
    esac && \
    tar -xzf /tmp/${HADOOP_TGZ} -C /opt && \
    chown -R root:root /opt/hadoop-${HADOOP_VERSION} && \
    ln -s hadoop-${HADOOP_VERSION} ${HADOOP_HOME} && \
    rm -f /tmp/${HADOOP_TGZ}

RUN set -eux && \
    groupadd -r supergroup && \
    useradd -G supergroup -r -M hdfs && \
    useradd -G supergroup -r -M yarn && \
    useradd -G supergroup -r -M mapred

RUN set -eux && \
    mkdir -p ${HADOOP_TMP_DIR} ${HADOOP_PID_DIR} /volumes/data /volumes/logs && \
    chgrp supergroup ${HADOOP_TMP_DIR} ${HADOOP_PID_DIR} /volumes/data /volumes/logs && \
    chmod 775 ${HADOOP_TMP_DIR} ${HADOOP_PID_DIR} /volumes/data /volumes/logs && \
    ln -s /volumes/data ${HADOOP_TMP_DIR}/dfs && \
    ln -s /volumes/logs ${HADOOP_LOG_DIR}

ARG HADOOP_MASTER_HOSTNAME
ENV HADOOP_MASTER_HOSTNAME=${HADOOP_MASTER_HOSTNAME}
COPY hadoop/etc/hadoop/* ${HADOOP_CONF_DIR}/
RUN set -eux && \
    find "${HADOOP_CONF_DIR}" -type f -print0 | xargs -0 sed -i "s/HADOOP_MASTER_HOSTNAME/${HADOOP_MASTER_HOSTNAME}/g"

COPY lib/common.sh hadoop/entrypoint/entrypoint-*.sh /entrypoint/
RUN set -eux && \
    chmod +x /entrypoint/entrypoint-*.sh

ENTRYPOINT ["/usr/bin/tini", "--"]

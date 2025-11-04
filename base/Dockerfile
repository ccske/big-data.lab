FROM ubuntu:24.04

RUN set -eux && userdel -f -r ubuntu

ARG DEBIAN_FRONTEND=noninteractive
RUN apt-get update && \
    apt-get upgrade -y && \
    apt-get install -y --no-install-recommends curl netcat-openbsd openjdk-11-jdk-headless procps gosu tini && \
    rm -rf /var/lib/apt/lists/*

ARG TARGETARCH
ENV HADOOP_VERSION=3.4.0
ENV HADOOP_HOME=/opt/hadoop
RUN set -eux && \
    case "${TARGETARCH:-unknown}" in \
      amd64)  HADOOP_TGZ="hadoop-${HADOOP_VERSION}.tar.gz" ;; \
      arm64)  HADOOP_TGZ="hadoop-${HADOOP_VERSION}-aarch64.tar.gz" ;; \
      *)      echo "Unsupported arch: ${TARGETARCH}"; exit 1 ;; \
    esac && \
    curl -fSL "https://downloads.apache.org/hadoop/common/hadoop-${HADOOP_VERSION}/${HADOOP_TGZ}" | tar -xz -C /opt && \
    ln -s hadoop-${HADOOP_VERSION} ${HADOOP_HOME}

ENV HIVE_VERSION=4.0.1
ENV HIVE_HOME=/opt/hive
RUN set -eux && \
    curl -fSL "https://downloads.apache.org/hive/hive-${HIVE_VERSION}/apache-hive-${HIVE_VERSION}-bin.tar.gz" | tar -xz -C /opt && \
    ln -s apache-hive-${HIVE_VERSION}-bin ${HIVE_HOME}

ENV PIG_VERSION=0.18.0
ENV PIG_HOME=/opt/pig
RUN set -eux && \
    curl -fSL "https://downloads.apache.org/pig/pig-${PIG_VERSION}/pig-${PIG_VERSION}.tar.gz" | tar -xz -C /opt && \
    ln -s pig-${PIG_VERSION} ${PIG_HOME}

RUN set -eux && \
    groupadd -r supergroup && \
    useradd -G supergroup -r -M hdfs && \
    useradd -G supergroup -r -M yarn && \
    useradd -G supergroup -r -M mapred && \
    useradd -G supergroup -r -M hive

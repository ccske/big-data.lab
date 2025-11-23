FROM ubuntu:24.04

RUN set -eux && userdel -f -r ubuntu

ARG DEBIAN_FRONTEND=noninteractive
RUN apt-get update && \
    apt-get upgrade -y && \
    apt-get install -y --no-install-recommends curl netcat-openbsd openjdk-11-jdk-headless procps gosu tini && \
    rm -rf /var/lib/apt/lists/*

RUN set -eux && \
    groupadd -r supergroup && \
    useradd -G supergroup -r -M hdfs && \
    useradd -G supergroup -r -M yarn && \
    useradd -G supergroup -r -M mapred && \
    useradd -G supergroup -r -M hive

COPY base/lib/common.sh /usr/local/bin/

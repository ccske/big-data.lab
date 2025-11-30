#!/usr/bin/env bash

set -euxo pipefail

#---
# Make sure the system is supported

if [[ -r "/etc/os-release" ]]; then
    source /etc/os-release
fi

if [[ "$ID" != "ubuntu" ]]; then
    echo "Error: Only Ubuntu Linux supported"
    exit 1
fi


#---
# Prepare user operating environment

ARCH=$(dpkg --print-architecture)
PROJECT_DIR=$(realpath "$(dirname "$0")")
BIN_DIRS=
ENV_FILE=".big-data.lab.env"
truncate -s 0 "${PROJECT_DIR}/${ENV_FILE}"

NP_SUDOERS=/etc/sudoers.d/nopasswd
NP_ENTRY="$USER ALL=(ALL) NOPASSWD: ALL"
if [[ ! -f "${NP_SUDOERS}" ]]; then
    sudo touch "${NP_SUDOERS}" && sudo chmod 0400 "${NP_SUDOERS}"
fi

if ! sudo grep -qxF "${NP_ENTRY}" "${NP_SUDOERS}"; then
    echo "${NP_ENTRY}" | sudo tee -a "${NP_SUDOERS}" > /dev/null
fi


#---
# Keep APT packages up-to-date and install packages required

sudo bash -c "
    export DEBIAN_FRONTEND=noninteractive
    apt-get update
    apt-get upgrade -y
    apt-get install -y ca-certificates curl mysql-client mysql-server net-tools openjdk-11-jdk ssh tmux vim
"

JAVA_HOME="$(dirname "$(dirname "$(readlink -f "$(which java)")")")"
echo "export JAVA_HOME=\"${JAVA_HOME}\"" | tee -a "${PROJECT_DIR}/${ENV_FILE}" > /dev/null


#---
# Set up Apache services

getent group supergroup > /dev/null 2>&1 || sudo groupadd -r supergroup

HADOOP_VERSION=3.4.0
echo "Set up Apache Hadoop v${HADOOP_VERSION} ($ARCH) in single-machine fully-distributed mode..."
HADOOP_HOME=/opt/hadoop
HADOOP_CONF_DIR=${HADOOP_HOME}/etc/hadoop
HADOOP_DATA_DIR=/var/lib/hadoop
HADOOP_LOG_DIR=/var/log/hadoop
HADOOP_PID_DIR=${HADOOP_DATA_DIR}
HADOOP_SBIN_DIR=${HADOOP_HOME}/sbin
HADOOP_SYSTEMD_DIR=${HADOOP_HOME}/systemd
case "${ARCH:-unknown}" in
  amd64)
      HADOOP_TGZ="hadoop-${HADOOP_VERSION}.tar.gz"
      ;;
  arm64)
      HADOOP_TGZ="hadoop-${HADOOP_VERSION}-aarch64.tar.gz"
      ;;
  *)
      echo "Unsupported arch: $ARCH"
      exit 1
      ;;
esac
HADOOP_TARBALL_URL="https://archive.apache.org/dist/hadoop/common/hadoop-${HADOOP_VERSION}/${HADOOP_TGZ}"

if [[ ! -d "${HADOOP_HOME}" ]]; then
    [[ -f "/tmp/${HADOOP_TGZ}" ]] || curl -fkSL "${HADOOP_TARBALL_URL}" -o /tmp/${HADOOP_TGZ}
    sudo tar --no-same-owner -xzf "/tmp/${HADOOP_TGZ}" -C /opt
    sudo mv -f /opt/hadoop-${HADOOP_VERSION} ${HADOOP_HOME}
#    rm -f "/tmp/${HADOOP_TGZ}"
    sudo cp -f ${PROJECT_DIR}/${HADOOP_CONF_DIR#/*/}/* ${HADOOP_CONF_DIR}/
    sudo sed -i \
        -e "s|>>JAVA_HOME<<|${JAVA_HOME}|g" \
        -e "s|>>HADOOP_LOG_DIR<<|${HADOOP_LOG_DIR}|g" \
        -e "s|>>HADOOP_PID_DIR<<|${HADOOP_PID_DIR}|g" \
        "${HADOOP_CONF_DIR}/hadoop-env.sh"
    echo "localhost" | sudo tee "${HADOOP_CONF_DIR}/workers"
    sudo cp -f ${PROJECT_DIR}/${HADOOP_SBIN_DIR#/*/}/* ${HADOOP_SBIN_DIR}/
    sudo mkdir ${HADOOP_SYSTEMD_DIR}
    sudo cp -f ${PROJECT_DIR}/${HADOOP_SYSTEMD_DIR#/*/}/hadoop.service ${HADOOP_SYSTEMD_DIR}/
    sudo ln -s ${HADOOP_SYSTEMD_DIR}/hadoop.service /etc/systemd/system/hadoop.service
fi

ITEMS=("DATA" "LOG")
for ITEM in "${ITEMS[@]}"; do
    DIR="HADOOP_${ITEM}_DIR"
    if [[ ! -d "${!DIR}" ]]; then
        sudo mkdir -p "${!DIR}"
        sudo chgrp supergroup "${!DIR}"
        sudo chmod 775 "${!DIR}"
    fi
done

HADOOP_ACCOUNTS=("hdfs" "yarn" "mapred")
for ACCOUNT in "${HADOOP_ACCOUNTS[@]}"; do
    if ! getent passwd "$ACCOUNT" > /dev/null 2>&1; then
        sudo useradd -G supergroup -r -m -d "/home/$ACCOUNT" "$ACCOUNT"
        uuidgen | sudo -u $ACCOUNT tee "/home/$ACCOUNT/hadoop-http-auth-signature-secret"
        sudo -u "$ACCOUNT" chmod 600 "/home/$ACCOUNT/hadoop-http-auth-signature-secret"
    fi
done

[[ -d "${HADOOP_DATA_DIR}/dfs/name/current" ]] || sudo -u hdfs ${HADOOP_HOME}/bin/hdfs namenode -format
sudo -u hdfs ${HADOOP_HOME}/bin/hdfs --daemon start namenode
sudo -u hdfs ${HADOOP_HOME}/bin/hdfs --daemon start datanode
${HADOOP_HOME}/bin/hdfs dfs -ls /tmp > /dev/null 2>&1 || ( \
    sudo -u hdfs ${HADOOP_HOME}/bin/hdfs dfs -mkdir /tmp && \
    sudo -u hdfs ${HADOOP_HOME}/bin/hdfs dfs -chmod 1777 /tmp \
)
sudo -u yarn ${HADOOP_HOME}/bin/yarn --daemon start resourcemanager
sudo -u yarn ${HADOOP_HOME}/bin/yarn --daemon start nodemanager
sudo -u mapred ${HADOOP_HOME}/bin/mapred --daemon start historyserver
sudo systemctl daemon-reload
sudo systemctl enable hadoop.service

getent group supergroup | grep -q $USER || sudo usermod -aG supergroup $USER
${HADOOP_HOME}/bin/hdfs dfs -ls /user/$USER > /dev/null 2>&1 || ( \
    sudo -u hdfs ${HADOOP_HOME}/bin/hdfs dfs -mkdir -p /user/$USER && \
    sudo -u hdfs ${HADOOP_HOME}/bin/hdfs dfs -chown $USER:supergroup /user/$USER
)
BIN_DIRS="${BIN_DIRS}:${HADOOP_HOME}/bin"


#TODO: Spark
SPARK_VERSION=3.5.7
echo "Set up Apache Spark v${SPARK_VERSION}..."
SPARK_TGZ="spark-${SPARK_VERSION}-bin-hadoop3.tgz"
SPARK_TARBALL_URL="https://archive.apache.org/dist/spark/spark-${SPARK_VERSION}/${SPARK_TGZ}"
SPARK_HOME=/opt/spark
if [[ ! -d "${SPARK_HOME}" ]]; then
    [[ -f "/tmp/${SPARK_TGZ}" ]] || curl -fkSL "${SPARK_TARBALL_URL}" -o /tmp/${SPARK_TGZ}
    sudo tar --no-same-owner -xzf "/tmp/${SPARK_TGZ}" -C /opt
    sudo ln -s spark-${SPARK_VERSION}-bin-hadoop3 ${SPARK_HOME}
#    rm -f /tmp/${SPARK_TGZ}
fi
BIN_DIRS="${BIN_DIRS}:${SPARK_HOME}/bin"

# TODO: Pig
PIG_VERSION=0.18.0
echo "Set up Apache Pig v${PIG_VERSION}..."
PIG_TGZ="pig-${PIG_VERSION}.tar.gz"
PIG_TARBALL_URL="https://archive.apache.org/dist/pig/pig-${PIG_VERSION}/${PIG_TGZ}"
PIG_HOME=/opt/pig
if [[ ! -d "${PIG_HOME}" ]]; then
    [[ -f "/tmp/${PIG_TGZ}" ]] || curl -fkSL "${PIG_TARBALL_URL}" -o /tmp/${PIG_TGZ}
    sudo tar --no-same-owner -xzf "/tmp/${PIG_TGZ}" -C /opt
    sudo ln -s pig-${PIG_VERSION} ${PIG_HOME}
#    rm -f /tmp/${PIG_TGZ}
fi
BIN_DIRS="${BIN_DIRS}:${PIG_HOME}/bin"

# TODO: Kafka
KAFKA_VERSION=3.9.1
SCALA_VERSION=2.12
echo "Set up Apache Kafka v${KAFKA_VERSION} (built with Scala v${SCALA_VERSION})..."
KAFKA_TGZ="kafka_${SCALA_VERSION}-${KAFKA_VERSION}.tgz"
KAFKA_TARBALL_URL="https://archive.apache.org/dist/kafka/${KAFKA_VERSION}/${KAFKA_TGZ}"
KAFKA_HOME=/opt/kafka
if [[ ! -d "${KAFKA_HOME}" ]]; then
    [[ -f "/tmp/${KAFKA_TGZ}" ]] || curl -fkSL "${KAFKA_TARBALL_URL}" -o /tmp/${KAFKA_TGZ}
    sudo tar --no-same-owner -xzf "/tmp/${KAFKA_TGZ}" -C /opt
    sudo ln -s kafka_${SCALA_VERSION}-${KAFKA_VERSION} ${KAFKA_HOME}
#    rm -f /tmp/${PIG_TGZ}
fi
BIN_DIRS="${BIN_DIRS}:${KAFKA_HOME}/bin"

printf "\n%s\n%s\n%s\n" \
    "if [[ \":\$PATH:\" != *\":${BIN_DIRS}:\"* ]]; then" \
    "    export PATH=\"${BIN_DIRS}:\$PATH\"" \
    "fi" | \
    tee -a "${PROJECT_DIR}/${ENV_FILE}" > /dev/null


#---
# Apply all changes

cp -f "${PROJECT_DIR}/${ENV_FILE}" "$HOME/"
if ! grep -qxF "    . ~/${ENV_FILE}" "$HOME/.bashrc"; then
    printf "\n%s\n%s\n%s\n" \
        "if [ -f ~/${ENV_FILE} ]; then" \
        "    . ~/${ENV_FILE}" \
        "fi" | \
        tee -a "$HOME/.bashrc" > /dev/null
fi

echo
echo ">>> Set up big-data.lab successfully! You may reboot the system to apply all changes."
echo

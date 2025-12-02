#!/usr/bin/env bash

set -euo pipefail

for arg in "$@"; do
    case "$arg" in
        --debug)
            set -x
            ;;
        *)
            ;;
    esac
done


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


#---
# Set up Apache services

export JAVA_HOME="$(dirname "$(dirname "$(readlink -f "$(which java)")")")"
echo "export JAVA_HOME=\"${JAVA_HOME}\"" | tee -a "${PROJECT_DIR}/${ENV_FILE}" > /dev/null

SUPER_USER_GROUP=supergroup
getent group ${SUPER_USER_GROUP} > /dev/null 2>&1 || sudo groupadd -r ${SUPER_USER_GROUP}

HADOOP_VERSION=3.4.0
echo "Set up Apache Hadoop v${HADOOP_VERSION} ($ARCH) in single-machine fully-distributed mode..."
HADOOP_HOME=/opt/hadoop
HADOOP_CONF_DIR=${HADOOP_HOME}/etc/hadoop
HADOOP_DATA_DIR=/var/lib/hadoop
HADOOP_LOG_DIR=/var/log/hadoop
HADOOP_PID_DIR=${HADOOP_DATA_DIR}
HADOOP_SBIN_DIR=${HADOOP_HOME}/sbin
HADOOP_SYSTEMD_DIR=${HADOOP_HOME}/systemd

HADOOP_SERVICE="hadoop.service"
if systemctl list-unit-files --type=service "${HADOOP_SERVICE}" > /dev/null 2>&1; then
    if sudo systemd-analyze verify "/etc/systemd/system/${HADOOP_SERVICE}" > /dev/null 2>&1; then
        sudo systemctl stop ${HADOOP_SERVICE}
        sudo systemctl disable ${HADOOP_SERVICE}
    fi
    sudo rm -f /etc/systemd/system/${HADOOP_SERVICE}
fi

for JPID in $(sudo jps | grep -E "NameNode|DataNode|ResourceManager|NodeManager|JobHistoryServer" | awk '{print $1}'); do
    sudo kill $JPID
done

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
    sudo tar --no-same-owner -xzf "/tmp/${HADOOP_TGZ}" -C /tmp
    sudo mv -f /tmp/hadoop-${HADOOP_VERSION} ${HADOOP_HOME}
    sudo cp -f ${PROJECT_DIR}/${HADOOP_CONF_DIR#/*/}/* ${HADOOP_CONF_DIR}/
    sudo sed -i \
        -e "s|{{JAVA_HOME}}|${JAVA_HOME}|g" \
        -e "s|{{HADOOP_LOG_DIR}}|${HADOOP_LOG_DIR}|g" \
        -e "s|{{HADOOP_PID_DIR}}|${HADOOP_PID_DIR}|g" \
        "${HADOOP_CONF_DIR}/hadoop-env.sh"
    echo "localhost" | sudo tee "${HADOOP_CONF_DIR}/workers"
    sudo cp -f ${PROJECT_DIR}/${HADOOP_SBIN_DIR#/*/}/* ${HADOOP_SBIN_DIR}/
    sudo cp -rf ${PROJECT_DIR}/${HADOOP_SYSTEMD_DIR#/*/} ${HADOOP_SYSTEMD_DIR}
fi

ITEMS=("DATA" "LOG")
for ITEM in "${ITEMS[@]}"; do
    DIR="HADOOP_${ITEM}_DIR"
    if [[ ! -d "${!DIR}" ]]; then
        sudo mkdir -p "${!DIR}"
        sudo chgrp ${SUPER_USER_GROUP} "${!DIR}"
        sudo chmod 775 "${!DIR}"
    fi
done

HADOOP_ACCOUNTS=("hdfs" "yarn" "mapred")
for ACCOUNT in "${HADOOP_ACCOUNTS[@]}"; do
    if ! getent passwd "$ACCOUNT" > /dev/null 2>&1; then
        sudo useradd -G ${SUPER_USER_GROUP} -r -m -d "/home/$ACCOUNT" "$ACCOUNT"
        uuidgen | sudo -u $ACCOUNT tee "/home/$ACCOUNT/hadoop-http-auth-signature-secret"
        sudo -u "$ACCOUNT" chmod 600 "/home/$ACCOUNT/hadoop-http-auth-signature-secret"
    fi
done

HADOOP_NATIVE_LID_DIR="${HADOOP_HOME}/lib/native"
export LD_LIBRARY_PATH="${HADOOP_NATIVE_LID_DIR}${LD_LIBRARY_PATH:+:}${LD_LIBRARY_PATH:-}"
printf "\n%s\n%s\n%s\n" \
    "if [[ \":\${LD_LIBRARY_PATH}:\" != *\":${HADOOP_NATIVE_LID_DIR}:\"* ]]; then" \
    "    export LD_LIBRARY_PATH=\"${HADOOP_NATIVE_LID_DIR}\${LD_LIBRARY_PATH:+:}\${LD_LIBRARY_PATH:-}\"" \
    "fi" | \
    tee -a "${PROJECT_DIR}/${ENV_FILE}" > /dev/null

[[ -d "${HADOOP_DATA_DIR}/dfs/name/current" ]] || sudo -u hdfs ${HADOOP_HOME}/bin/hdfs namenode -format
sudo -u hdfs ${HADOOP_HOME}/bin/hdfs --daemon start namenode
sudo -u hdfs ${HADOOP_HOME}/bin/hdfs --daemon start datanode
${HADOOP_HOME}/bin/hdfs dfs -ls /tmp > /dev/null 2>&1 || ( \
    sudo -u hdfs ${HADOOP_HOME}/bin/hdfs dfs -mkdir /tmp && \
    sudo -u hdfs ${HADOOP_HOME}/bin/hdfs dfs -chmod 1777 /tmp \
)
sudo -u hdfs ${HADOOP_HOME}/bin/hdfs --daemon stop datanode
sudo -u hdfs ${HADOOP_HOME}/bin/hdfs --daemon stop namenode

sudo ln -s ${HADOOP_SYSTEMD_DIR}/${HADOOP_SERVICE} /etc/systemd/system/${HADOOP_SERVICE}
sudo systemctl daemon-reload
sudo systemctl restart ${HADOOP_SERVICE}
sudo systemctl enable ${HADOOP_SERVICE}

getent group ${SUPER_USER_GROUP} | grep -q $USER || sudo usermod -aG ${SUPER_USER_GROUP} $USER
${HADOOP_HOME}/bin/hdfs dfs -ls /user/$USER > /dev/null 2>&1 || ( \
    sudo -u hdfs ${HADOOP_HOME}/bin/hdfs dfs -mkdir -p /user/$USER && \
    sudo -u hdfs ${HADOOP_HOME}/bin/hdfs dfs -chown $USER:${SUPER_USER_GROUP} /user/$USER
)

echo | tee -a "${PROJECT_DIR}/${ENV_FILE}" > /dev/null
echo "export HADOOP_HOME=\"${HADOOP_HOME}\"" | tee -a "${PROJECT_DIR}/${ENV_FILE}" > /dev/null
echo "export HADOOP_CONF_DIR=\"${HADOOP_HOME}/etc/hadoop\"" | tee -a "${PROJECT_DIR}/${ENV_FILE}" > /dev/null
BIN_DIRS="${HADOOP_HOME}/bin"


SPARK_VERSION=3.5.7
SCALA_VERSION=2.13
echo "Set up Apache Spark v${SPARK_VERSION} (built with Scala v${SCALA_VERSION}) in client mode on YARN..."
SPARK_HOME=/opt/spark
SPARK_CONF_DIR=${SPARK_HOME}/conf
SPARK_LOG_DIR=/var/log/spark
SPARK_PID_DIR=/var/lib/spark
SPARK_SYSTEMD_DIR=${SPARK_HOME}/systemd

SPARK_HISTORYSERVER_SERVICE="spark-historyserver.service"
if systemctl list-unit-files --type=service "${SPARK_HISTORYSERVER_SERVICE}" > /dev/null 2>&1; then
    if sudo systemd-analyze verify "/etc/systemd/system/${SPARK_HISTORYSERVER_SERVICE}" > /dev/null 2>&1; then
        sudo systemctl stop ${SPARK_HISTORYSERVER_SERVICE}
        sudo systemctl disable ${SPARK_HISTORYSERVER_SERVICE}
    fi
    sudo rm -f /etc/systemd/system/${SPARK_HISTORYSERVER_SERVICE}
fi

for JPID in $(sudo jps -l | grep -E "org.apache.spark.deploy.history.HistoryServer" | awk '{print $1}'); do
    sudo kill $JPID
done

SPARK_TGZ="spark-${SPARK_VERSION}-bin-hadoop3-scala${SCALA_VERSION}.tgz"
SPARK_TARBALL_URL="https://archive.apache.org/dist/spark/spark-${SPARK_VERSION}/${SPARK_TGZ}"
if [[ ! -d "${SPARK_HOME}" ]]; then
    [[ -f "/tmp/${SPARK_TGZ}" ]] || curl -fkSL "${SPARK_TARBALL_URL}" -o /tmp/${SPARK_TGZ}
    sudo tar --no-same-owner -xzf "/tmp/${SPARK_TGZ}" -C /tmp
    sudo mv -f /tmp/spark-${SPARK_VERSION}-bin-hadoop3-scala${SCALA_VERSION} ${SPARK_HOME}
    sudo cp -f ${PROJECT_DIR}/${SPARK_CONF_DIR#/*/}/* ${SPARK_CONF_DIR}/
    sudo sed -i \
        -e "s|{{HADOOP_NATIVE_LID_DIR}}|${HADOOP_NATIVE_LID_DIR}|g" \
        -e "s|{{HADOOP_CONF_DIR}}|${HADOOP_CONF_DIR}|g" \
        -e "s|{{SPARK_LOG_DIR}}|${SPARK_LOG_DIR}|g" \
        -e "s|{{SPARK_PID_DIR}}|${SPARK_PID_DIR}|g" \
        "${SPARK_CONF_DIR}/spark-env.sh"
    sudo cp -rf ${PROJECT_DIR}/${SPARK_SYSTEMD_DIR#/*/} ${SPARK_SYSTEMD_DIR}
fi

ITEMS=("LOG" "PID")
for ITEM in "${ITEMS[@]}"; do
    DIR="SPARK_${ITEM}_DIR"
    if [[ ! -d "${!DIR}" ]]; then
        sudo mkdir -p "${!DIR}"
        sudo chgrp ${SUPER_USER_GROUP} "${!DIR}"
        sudo chmod 775 "${!DIR}"
    fi
done

SPARK_ACCOUNT="spark"
if ! getent passwd "${SPARK_ACCOUNT}" > /dev/null 2>&1; then
    sudo useradd -G ${SUPER_USER_GROUP} -r -m -d "/home/${SPARK_ACCOUNT}" "${SPARK_ACCOUNT}"
fi

${HADOOP_HOME}/bin/hdfs dfs -ls /shared/spark-logs > /dev/null 2>&1 || ( \
    sudo -u hdfs ${HADOOP_HOME}/bin/hdfs dfs -mkdir -p /shared/spark-logs && \
    sudo -u hdfs ${HADOOP_HOME}/bin/hdfs dfs -chown ${SPARK_ACCOUNT}:${SUPER_USER_GROUP} /shared/spark-logs && \
    sudo -u hdfs ${HADOOP_HOME}/bin/hdfs dfs -chmod 775 /shared/spark-logs \
)
${HADOOP_HOME}/bin/hdfs dfs -ls /shared/spark-dist > /dev/null 2>&1 || ( \
    sudo -u spark ${HADOOP_HOME}/bin/hdfs dfs -mkdir -p /shared/spark-dist && \
    sudo -u spark ${HADOOP_HOME}/bin/hdfs dfs -put ${SPARK_HOME}/jars /shared/spark-dist/ \
)

sudo ln -s ${SPARK_SYSTEMD_DIR}/${SPARK_HISTORYSERVER_SERVICE} /etc/systemd/system/${SPARK_HISTORYSERVER_SERVICE}
sudo systemctl daemon-reload
sudo systemctl restart ${SPARK_HISTORYSERVER_SERVICE}
sudo systemctl enable ${SPARK_HISTORYSERVER_SERVICE}

echo | tee -a "${PROJECT_DIR}/${ENV_FILE}" > /dev/null
echo "export SPARK_HOME=\"${SPARK_HOME}\"" | tee -a "${PROJECT_DIR}/${ENV_FILE}" > /dev/null
echo "export SPARK_CONF_DIR=\"${SPARK_HOME}/conf\"" | tee -a "${PROJECT_DIR}/${ENV_FILE}" > /dev/null
BIN_DIRS="${BIN_DIRS}:${SPARK_HOME}/bin"


PIG_VERSION=0.18.0
echo "Set up Apache Pig v${PIG_VERSION}..."
PIG_HOME=/opt/pig

PIG_TGZ="pig-${PIG_VERSION}.tar.gz"
PIG_TARBALL_URL="https://archive.apache.org/dist/pig/pig-${PIG_VERSION}/${PIG_TGZ}"
if [[ ! -d "${PIG_HOME}" ]]; then
    [[ -f "/tmp/${PIG_TGZ}" ]] || curl -fkSL "${PIG_TARBALL_URL}" -o /tmp/${PIG_TGZ}
    sudo tar --no-same-owner -xzf "/tmp/${PIG_TGZ}" -C /tmp
    sudo mv -f /tmp/pig-${PIG_VERSION} ${PIG_HOME}
    sudo sed -i "s/^pig\.ats\.enabled=true/pig.ats.enabled=false/" "${PIG_HOME}/conf/pig.properties"
fi

echo | tee -a "${PROJECT_DIR}/${ENV_FILE}" > /dev/null
echo "export PIG_HOME=\"${PIG_HOME}\"" | tee -a "${PROJECT_DIR}/${ENV_FILE}" > /dev/null
echo "export PIG_CONF_DIR=\"${PIG_HOME}/conf\"" | tee -a "${PROJECT_DIR}/${ENV_FILE}" > /dev/null
BIN_DIRS="${BIN_DIRS}:${PIG_HOME}/bin"


# TODO: Kafka
KAFKA_VERSION=3.9.1
echo "Set up Apache Kafka v${KAFKA_VERSION} (built with Scala v${SCALA_VERSION})..."
KAFKA_TGZ="kafka_${SCALA_VERSION}-${KAFKA_VERSION}.tgz"
KAFKA_TARBALL_URL="https://archive.apache.org/dist/kafka/${KAFKA_VERSION}/${KAFKA_TGZ}"
KAFKA_HOME=/opt/kafka
if [[ ! -d "${KAFKA_HOME}" ]]; then
    [[ -f "/tmp/${KAFKA_TGZ}" ]] || curl -fkSL "${KAFKA_TARBALL_URL}" -o /tmp/${KAFKA_TGZ}
    sudo tar --no-same-owner -xzf "/tmp/${KAFKA_TGZ}" -C /opt
    sudo ln -s kafka_${SCALA_VERSION}-${KAFKA_VERSION} ${KAFKA_HOME}
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

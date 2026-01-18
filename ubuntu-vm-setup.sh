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

NP_SUDOERS=/etc/sudoers.d/nopasswd
NP_ENTRY="$USER ALL=(ALL) NOPASSWD: ALL"
if [[ ! -f "${NP_SUDOERS}" ]]; then
    sudo touch "${NP_SUDOERS}" && sudo chmod 0400 "${NP_SUDOERS}"
fi

if ! sudo grep -qxF "${NP_ENTRY}" "${NP_SUDOERS}"; then
    echo "${NP_ENTRY}" | sudo tee -a "${NP_SUDOERS}" > /dev/null
fi

HOSTS_ENTRY="127.0.0.1 $(hostname -s)"
if ! grep -qxF "${HOSTS_ENTRY}" "/etc/hosts"; then
    echo | sudo tee -a "/etc/hosts" > /dev/null
    echo "${HOSTS_ENTRY}" | sudo tee -a "/etc/hosts" > /dev/null
fi


#---
# Keep APT packages up-to-date and install packages required

sudo DEBIAN_FRONTEND=noninteractive apt-get update
sudo DEBIAN_FRONTEND=noninteractive apt-get upgrade -y
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y ca-certificates curl mysql-client mysql-server net-tools openjdk-11-jdk ssh tmux vim


#---
# Set up Apache services

JAVA_HOME="$(dirname "$(dirname "$(readlink -f "$(which java)")")")"

HADOOP_VERSION=3.4.0
echo "Set up Apache Hadoop v${HADOOP_VERSION} ($ARCH) in single-machine fully-distributed mode..."
HADOOP_HOME=/opt/hadoop
HADOOP_CONF_DIR=${HADOOP_HOME}/etc/hadoop
HADOOP_DATA_DIR=/var/lib/hadoop
HADOOP_LOG_DIR=/var/log/hadoop
HADOOP_PID_DIR=${HADOOP_DATA_DIR}
HADOOP_SYSTEMD_DIR=${HADOOP_HOME}/systemd

HADOOP_USER=hadoop
HADOOP_GROUP=${HADOOP_USER}
HDFS_USER=hdfs
YARN_USER=yarn
MAPRED_USER=mapred

HDFS_SHARED_DIR=/shared
HDFS_TMP_DIR=/tmp

HADOOP_NATIVE_LIB_DIR="${HADOOP_HOME}/lib/native"

getent passwd ${HADOOP_USER} > /dev/null 2>&1 || sudo useradd -r -m -d /home/${HADOOP_USER} ${HADOOP_USER}
for ACCOUNT in ${HDFS_USER} ${YARN_USER} ${MAPRED_USER}; do
    if ! getent passwd $ACCOUNT > /dev/null 2>&1; then
        sudo useradd -G ${HADOOP_GROUP} -r -m -d /home/$ACCOUNT $ACCOUNT
        uuidgen | sudo -u $ACCOUNT tee "/home/$ACCOUNT/hadoop-http-auth-signature-secret"
        sudo -u $ACCOUNT chmod 0600 "/home/$ACCOUNT/hadoop-http-auth-signature-secret"
    fi
done

if [[ ! -d "${HADOOP_HOME}" ]]; then
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
    [[ -f "/tmp/${HADOOP_TGZ}" ]] || curl -fkSL "${HADOOP_TARBALL_URL}" -o /tmp/${HADOOP_TGZ}
    sudo tar -xzf "/tmp/${HADOOP_TGZ}" --no-same-owner -C /tmp
    sudo mv -f /tmp/hadoop-${HADOOP_VERSION} ${HADOOP_HOME}

    sudo install -o ${HADOOP_USER} -g ${HADOOP_GROUP} -m 0775 -d ${HADOOP_DATA_DIR} ${HADOOP_LOG_DIR}

    sudo install -m 0644 -t ${HADOOP_CONF_DIR} "${PROJECT_DIR}/${HADOOP_CONF_DIR#/*/}"/*
    sudo sed -i \
        -e "s|{{JAVA_HOME}}|${JAVA_HOME}|g" \
        -e "s|{{HADOOP_HOME}}|${HADOOP_HOME}|g" \
        -e "s|{{HADOOP_CONF_DIR}}|${HADOOP_CONF_DIR}|g" \
        -e "s|{{HADOOP_LOG_DIR}}|${HADOOP_LOG_DIR}|g" \
        -e "s|{{HADOOP_PID_DIR}}|${HADOOP_PID_DIR}|g" \
        "${HADOOP_CONF_DIR}/hadoop-env.sh"
    sudo sed -i -e "s|{{HADOOP_HOME}}|${HADOOP_HOME}|g" "${HADOOP_CONF_DIR}/mapred-site.xml"

    [[ -d "${HADOOP_DATA_DIR}/dfs/name/current" ]] || sudo -u ${HDFS_USER} -g ${HADOOP_GROUP} ${HADOOP_HOME}/bin/hdfs namenode -format
    sudo -u ${HDFS_USER} -g ${HADOOP_GROUP} ${HADOOP_HOME}/bin/hdfs --daemon start namenode
    sudo -u ${HDFS_USER} -g ${HADOOP_GROUP} ${HADOOP_HOME}/bin/hdfs --daemon start datanode
    ${HADOOP_HOME}/bin/hdfs dfs -ls ${HDFS_SHARED_DIR} > /dev/null 2>&1 || ( \
        sudo -u ${HDFS_USER} -g ${HADOOP_GROUP} ${HADOOP_HOME}/bin/hdfs dfs -mkdir ${HDFS_SHARED_DIR} && \
        sudo -u ${HDFS_USER} -g ${HADOOP_GROUP} ${HADOOP_HOME}/bin/hdfs dfs -chmod 1775 ${HDFS_SHARED_DIR} \
    )
    ${HADOOP_HOME}/bin/hdfs dfs -ls ${HDFS_TMP_DIR} > /dev/null 2>&1 || ( \
        sudo -u ${HDFS_USER} -g ${HADOOP_GROUP} ${HADOOP_HOME}/bin/hdfs dfs -mkdir ${HDFS_TMP_DIR} && \
        sudo -u ${HDFS_USER} -g ${HADOOP_GROUP} ${HADOOP_HOME}/bin/hdfs dfs -chmod 1777 ${HDFS_TMP_DIR} \
    )
    getent group ${HADOOP_GROUP} | grep -q $USER || sudo usermod -aG ${HADOOP_GROUP} $USER
    ${HADOOP_HOME}/bin/hdfs dfs -ls /user/$USER > /dev/null 2>&1 || ( \
        sudo -u ${HDFS_USER} -g ${HADOOP_GROUP} ${HADOOP_HOME}/bin/hdfs dfs -mkdir -p /user/$USER && \
        sudo -u ${HDFS_USER} -g ${HADOOP_GROUP} ${HADOOP_HOME}/bin/hdfs dfs -chown $USER:${HADOOP_GROUP} /user/$USER
    )
    sudo -u ${HDFS_USER} -g ${HADOOP_GROUP} ${HADOOP_HOME}/bin/hdfs --daemon stop datanode
    sudo -u ${HDFS_USER} -g ${HADOOP_GROUP} ${HADOOP_HOME}/bin/hdfs --daemon stop namenode

    sudo install -m 0755 -d ${HADOOP_SYSTEMD_DIR}
    for UNIT_FILE_PATH in "${PROJECT_DIR}/${HADOOP_SYSTEMD_DIR#/*/}"/*; do
        UNIT_FILE=$(basename ${UNIT_FILE_PATH})
        sudo install -m 0644 -t ${HADOOP_SYSTEMD_DIR} ${UNIT_FILE_PATH}
        sudo sed -i \
            -e "s|{{HADOOP_HOME}}|${HADOOP_HOME}|g" \
            -e "s|{{HADOOP_PID_DIR}}|${HADOOP_PID_DIR}|g" \
            -e "s|{{HADOOP_GROUP}}|${HADOOP_GROUP}|g" \
            -e "s|{{HDFS_USER}}|${HDFS_USER}|g" \
            -e "s|{{YARN_USER}}|${YARN_USER}|g" \
            -e "s|{{MAPRED_USER}}|${MAPRED_USER}|g" \
            "${HADOOP_SYSTEMD_DIR}/${UNIT_FILE}"
        sudo ln -sf ${HADOOP_SYSTEMD_DIR}/${UNIT_FILE} /etc/systemd/system/${UNIT_FILE}
    done
    sudo systemctl daemon-reload
    for UNIT_FILE_PATH in "${HADOOP_SYSTEMD_DIR}"/*; do
        UNIT_FILE=$(basename ${UNIT_FILE_PATH})
        sudo systemctl enable ${UNIT_FILE}
    done
    sudo systemctl start hadoop.target
fi


SPARK_VERSION=3.5.8
SCALA_VERSION=2.13
echo "Set up Apache Spark v${SPARK_VERSION} (built with Scala v${SCALA_VERSION}) in client mode on YARN..."
SPARK_HOME=/opt/spark
SPARK_CONF_DIR=${SPARK_HOME}/conf
SPARK_LOG_DIR=/var/log/spark
SPARK_PID_DIR=/var/lib/spark
SPARK_SYSTEMD_DIR=${SPARK_HOME}/systemd

SPARK_USER=spark
SPARK_GROUP=${SPARK_USER}

HDFS_SPARK_DIST_DIR=${HDFS_SHARED_DIR}/spark-dist
HDFS_SPARK_LOGS_DIR=${HDFS_SHARED_DIR}/spark-logs

if ! getent passwd ${SPARK_USER} > /dev/null 2>&1; then
    sudo useradd -G ${HADOOP_GROUP} -r -m -d /home/${SPARK_USER} ${SPARK_USER}
fi

if [[ ! -d "${SPARK_HOME}" ]]; then
    for JPID in $(sudo jps -l | grep -E "org.apache.spark.deploy.history.HistoryServer" | awk '{print $1}'); do
        sudo kill $JPID
    done

    SPARK_TGZ="spark-${SPARK_VERSION}-bin-hadoop3-scala${SCALA_VERSION}.tgz"
    SPARK_TARBALL_URL="https://archive.apache.org/dist/spark/spark-${SPARK_VERSION}/${SPARK_TGZ}"
    [[ -f "/tmp/${SPARK_TGZ}" ]] || curl -fkSL "${SPARK_TARBALL_URL}" -o /tmp/${SPARK_TGZ}
    sudo tar -xzf "/tmp/${SPARK_TGZ}" --no-same-owner -C /tmp
    sudo mv -f /tmp/spark-${SPARK_VERSION}-bin-hadoop3-scala${SCALA_VERSION} ${SPARK_HOME}

    sudo install -o ${SPARK_USER} -g ${SPARK_GROUP} -m 0755 -d ${SPARK_LOG_DIR} ${SPARK_PID_DIR}

    sudo install -m 0644 -t ${SPARK_CONF_DIR} "${PROJECT_DIR}/${SPARK_CONF_DIR#/*/}/spark-defaults.conf"
    sudo sed -i \
        -e "s|{{HDFS_SPARK_DIST_DIR}}|${HDFS_SPARK_DIST_DIR}|g" \
        -e "s|{{HDFS_SPARK_LOGS_DIR}}|${HDFS_SPARK_LOGS_DIR}|g" \
        "${SPARK_CONF_DIR}/spark-defaults.conf"
    sudo install -m 0755 -t ${SPARK_CONF_DIR} "${PROJECT_DIR}/${SPARK_CONF_DIR#/*/}/spark-env.sh"
    sudo sed -i \
        -e "s|{{HADOOP_NATIVE_LIB_DIR}}|${HADOOP_NATIVE_LIB_DIR}|g" \
        -e "s|{{HADOOP_CONF_DIR}}|${HADOOP_CONF_DIR}|g" \
        -e "s|{{SPARK_LOG_DIR}}|${SPARK_LOG_DIR}|g" \
        -e "s|{{SPARK_PID_DIR}}|${SPARK_PID_DIR}|g" \
        "${SPARK_CONF_DIR}/spark-env.sh"

    ${HADOOP_HOME}/bin/hdfs dfs -ls ${HDFS_SPARK_DIST_DIR} > /dev/null 2>&1 || ( \
        sudo -u ${SPARK_USER} -g ${HADOOP_GROUP} ${HADOOP_HOME}/bin/hdfs dfs -mkdir ${HDFS_SPARK_DIST_DIR} && \
        sudo -u ${SPARK_USER} -g ${HADOOP_GROUP} ${HADOOP_HOME}/bin/hdfs dfs -put ${SPARK_HOME}/jars ${HDFS_SPARK_DIST_DIR}/ \
    )
    ${HADOOP_HOME}/bin/hdfs dfs -ls ${HDFS_SPARK_LOGS_DIR} > /dev/null 2>&1 || ( \
        sudo -u ${SPARK_USER} -g ${HADOOP_GROUP} ${HADOOP_HOME}/bin/hdfs dfs -mkdir ${HDFS_SPARK_LOGS_DIR} \
    )

    sudo install -m 0755 -d ${SPARK_SYSTEMD_DIR}
    sudo install -m 0644 -t ${SPARK_SYSTEMD_DIR} "${PROJECT_DIR}/${SPARK_SYSTEMD_DIR#/*/}"/*
    UNIT_FILE=spark-historyserver.service
    sudo sed -i \
        -e "s|{{SPARK_HOME}}|${SPARK_HOME}|g" \
        -e "s|{{SPARK_PID_DIR}}|${SPARK_PID_DIR}|g" \
        -e "s|{{SPARK_USER}}|${SPARK_USER}|g" \
        -e "s|{{HADOOP_GROUP}}|${HADOOP_GROUP}|g" \
        "${SPARK_SYSTEMD_DIR}/${UNIT_FILE}"
    sudo ln -sf ${SPARK_SYSTEMD_DIR}/${UNIT_FILE} /etc/systemd/system/${UNIT_FILE}
    sudo systemctl daemon-reload
    sudo systemctl enable ${UNIT_FILE}
    sudo systemctl start ${UNIT_FILE}
fi


PIG_VERSION=0.18.0
echo "Set up Apache Pig v${PIG_VERSION}..."
PIG_HOME=/opt/pig
PIG_CONF_DIR=${PIG_HOME}/conf

if [[ ! -d "${PIG_HOME}" ]]; then
    PIG_TGZ="pig-${PIG_VERSION}.tar.gz"
    PIG_TARBALL_URL="https://archive.apache.org/dist/pig/pig-${PIG_VERSION}/${PIG_TGZ}"
    [[ -f "/tmp/${PIG_TGZ}" ]] || curl -fkSL "${PIG_TARBALL_URL}" -o /tmp/${PIG_TGZ}
    sudo tar -xzf "/tmp/${PIG_TGZ}" --no-same-owner -C /tmp
    sudo mv -f /tmp/pig-${PIG_VERSION} ${PIG_HOME}
    sudo install -m 0644 -t ${PIG_CONF_DIR} "${PROJECT_DIR}/${PIG_CONF_DIR#/*/}/pig.properties"
fi


KAFKA_VERSION=3.9.1
echo "Set up Apache Kafka v${KAFKA_VERSION} (built with Scala v${SCALA_VERSION})..."
KAFKA_HOME=/opt/kafka
KAFKA_CONF_DIR=${KAFKA_HOME}/config
KAFKA_DATA_DIR=/var/lib/kafka
KAFKA_LOG_DIR=/var/log/kafka
KAFKA_SYSTEMD_DIR=${KAFKA_HOME}/systemd

KAFKA_USER=kafka
KAFKA_GROUP=${KAFKA_USER}

KRAFT_CONF_DIR=${KAFKA_CONF_DIR}/kraft
KRAFT_CONF_FILE=${KRAFT_CONF_DIR}/server.properties

if ! getent passwd ${KAFKA_USER} > /dev/null 2>&1; then
    sudo useradd -G ${HADOOP_GROUP} -r -m -d /home/${KAFKA_USER} ${KAFKA_USER}
fi

if [[ ! -d "${KAFKA_HOME}" ]]; then
    for JPID in $(sudo jps -l | grep -E "kafka.Kafka" | awk '{print $1}'); do
        sudo kill $JPID
    done

    KAFKA_TGZ="kafka_${SCALA_VERSION}-${KAFKA_VERSION}.tgz"
    KAFKA_TARBALL_URL="https://archive.apache.org/dist/kafka/${KAFKA_VERSION}/${KAFKA_TGZ}"
    [[ -f "/tmp/${KAFKA_TGZ}" ]] || curl -fkSL "${KAFKA_TARBALL_URL}" -o /tmp/${KAFKA_TGZ}
    sudo tar -xzf "/tmp/${KAFKA_TGZ}" --no-same-owner -C /tmp
    sudo mv -f /tmp/kafka_${SCALA_VERSION}-${KAFKA_VERSION} ${KAFKA_HOME}

    sudo install -o ${KAFKA_USER} -g ${KAFKA_GROUP} -m 0755 -d ${KAFKA_DATA_DIR} ${KAFKA_LOG_DIR}

    sudo install -m 0755 -d ${KRAFT_CONF_DIR}
    sudo install -m 0644 -t ${KRAFT_CONF_DIR} "${PROJECT_DIR}/${KRAFT_CONF_FILE#/*/}"
    sudo sed -i -e "s|{{KAFKA_DATA_DIR}}|${KAFKA_DATA_DIR}|g" "${KRAFT_CONF_FILE}"

    if [[ ! -f "${KAFKA_DATA_DIR}/meta.properties" ]]; then
        CLUSTER_ID=$($KAFKA_HOME/bin/kafka-storage.sh random-uuid)
        sudo -u ${KAFKA_USER} ${KAFKA_HOME}/bin/kafka-storage.sh format --config "${KRAFT_CONF_FILE}" --cluster-id ${CLUSTER_ID} --ignore-formatted
    fi

    sudo install -m 0755 -d ${KAFKA_SYSTEMD_DIR}
    sudo install -m 0644 -t ${KAFKA_SYSTEMD_DIR} "${PROJECT_DIR}/${KAFKA_SYSTEMD_DIR#/*/}"/*
    UNIT_FILE=kafka.service
    sudo sed -i \
        -e "s|{{KAFKA_HOME}}|${KAFKA_HOME}|g" \
        -e "s|{{KAFKA_LOG_DIR}}|${KAFKA_LOG_DIR}|g" \
        -e "s|{{KRAFT_CONF_FILE}}|${KRAFT_CONF_FILE}|g" \
        -e "s|{{KAFKA_USER}}|${KAFKA_USER}|g" \
        -e "s|{{KAFKA_GROUP}}|${KAFKA_GROUP}|g" \
        "${KAFKA_SYSTEMD_DIR}/${UNIT_FILE}"
    sudo ln -sf ${KAFKA_SYSTEMD_DIR}/${UNIT_FILE} /etc/systemd/system/${UNIT_FILE}
    sudo systemctl daemon-reload
    sudo systemctl enable ${UNIT_FILE}
    sudo systemctl start ${UNIT_FILE}
fi


#---
# Apply all changes

ENV_FILE=".big-data.lab.env"
truncate -s 0 "${PROJECT_DIR}/${ENV_FILE}"
echo "export JAVA_HOME=\"${JAVA_HOME}\"" | tee -a "${PROJECT_DIR}/${ENV_FILE}" > /dev/null
echo "export HADOOP_HOME=\"${HADOOP_HOME}\"" | tee -a "${PROJECT_DIR}/${ENV_FILE}" > /dev/null
echo "export HADOOP_CONF_DIR=\"${HADOOP_CONF_DIR}\"" | tee -a "${PROJECT_DIR}/${ENV_FILE}" > /dev/null
echo "export SPARK_HOME=\"${SPARK_HOME}\"" | tee -a "${PROJECT_DIR}/${ENV_FILE}" > /dev/null
echo "export SPARK_CONF_DIR=\"${SPARK_CONF_DIR}\"" | tee -a "${PROJECT_DIR}/${ENV_FILE}" > /dev/null
echo "export PIG_HOME=\"${PIG_HOME}\"" | tee -a "${PROJECT_DIR}/${ENV_FILE}" > /dev/null
echo "export PIG_CONF_DIR=\"${PIG_CONF_DIR}\"" | tee -a "${PROJECT_DIR}/${ENV_FILE}" > /dev/null
echo "export KAFKA_HOME=\"${KAFKA_HOME}\"" | tee -a "${PROJECT_DIR}/${ENV_FILE}" > /dev/null
echo "export KAFKA_CONF_DIR=\"${KAFKA_CONF_DIR}\"" | tee -a "${PROJECT_DIR}/${ENV_FILE}" > /dev/null

printf "\n%s\n%s\n%s\n" \
    "if [[ \":\${LD_LIBRARY_PATH}:\" != *\":${HADOOP_NATIVE_LIB_DIR}:\"* ]]; then" \
    "    export LD_LIBRARY_PATH=\"${HADOOP_NATIVE_LIB_DIR}\${LD_LIBRARY_PATH:+:}\${LD_LIBRARY_PATH:-}\"" \
    "fi" | \
    tee -a "${PROJECT_DIR}/${ENV_FILE}" > /dev/null

BIN_DIRS="${HADOOP_HOME}/bin:${SPARK_HOME}/bin:${PIG_HOME}/bin:${KAFKA_HOME}/bin"
printf "\n%s\n%s\n%s\n" \
    "if [[ \":\$PATH:\" != *\":${BIN_DIRS}:\"* ]]; then" \
    "    export PATH=\"${BIN_DIRS}:\$PATH\"" \
    "fi" | \
    tee -a "${PROJECT_DIR}/${ENV_FILE}" > /dev/null

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

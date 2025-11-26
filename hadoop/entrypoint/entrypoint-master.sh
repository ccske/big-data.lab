#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
source "${SCRIPT_DIR}/common.sh"

JAVA_HOME="$(dirname "$(dirname "$(readlink -f "$(which java)")")")"

if [[ -n "${USER_NAME-}" && -n "${USER_ID-}" && -n "${GROUP_NAME-}" && -n "${GROUP_ID-}" ]]; then
    getent group ${GROUP_NAME} > /dev/null 2>&1 || groupadd -g ${GROUP_ID} ${GROUP_NAME}
    getent passwd ${USER_NAME} > /dev/null 2>&1 || useradd -u ${USER_ID} -g ${GROUP_NAME} -G supergroup -M ${USER_NAME}
fi

if [[ ! -d "${HADOOP_TMP_DIR}/dfs/name/current" ]]; then
  echo "Formatting NameNode..."
  gosu hdfs bash -lc "${HADOOP_HOME}/bin/hdfs namenode -format -force -nonInteractive"
fi

gosu hdfs bash -lc "${HADOOP_HOME}/bin/hdfs --daemon start namenode"
wait_until_service_up "${HOSTNAME}" "9870" || exit 1

gosu yarn bash -lc "${HADOOP_HOME}/bin/yarn --daemon start resourcemanager"
wait_until_service_up "${HOSTNAME}" "8088" || exit 1

gosu hdfs bash -lc "${HADOOP_HOME}/bin/hdfs dfs -ls /tmp > /dev/null 2>&1 || ( ${HADOOP_HOME}/bin/hdfs dfs -mkdir /tmp && ${HADOOP_HOME}/bin/hdfs dfs -chmod 1777 /tmp )"
gosu hdfs bash -lc "${HADOOP_HOME}/bin/hdfs dfs -ls /user > /dev/null 2>&1 || ${HADOOP_HOME}/bin/hdfs dfs -mkdir /user"

if [[ -n "${USER_NAME-}" && -n "${USER_ID-}" && -n "${GROUP_NAME-}" && -n "${GROUP_ID-}" ]]; then
    gosu ${USER_NAME} bash -lc "${HADOOP_HOME}/bin/hdfs dfs -ls /user/${USER_NAME} 2> /dev/null || ${HADOOP_HOME}/bin/hdfs dfs -mkdir /user/${USER_NAME}"
fi

gosu mapred bash -lc "${HADOOP_HOME}/bin/mapred --daemon start historyserver"
wait_until_service_up "${HOSTNAME}" "19888" || exit 1

echo "Hadoop Master Services started: NameNode (hdfs), ResourceManager (yarn), HistoryServer (mapred)."

trap '
    echo "Stopping Hadoop Master..."; \
    gosu mapred bash -lc "${HADOOP_HOME}/bin/mapred --daemon stop historyserver" || true; \
    gosu yarn bash -lc "${HADOOP_HOME}/bin/yarn --daemon stop resourcemanager" || true; \
    gosu hdfs bash -lc "${HADOOP_HOME}/bin/hdfs --daemon stop namenode" || true; \
    exit 0 \
    ' SIGTERM SIGINT

tail -f /dev/null & wait $!

#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
source "${SCRIPT_DIR}/common.sh"

JAVA_HOME="$(dirname "$(dirname "$(readlink -f "$(which java)")")")"

if [[ -n "${USER_NAME-}" && -n "${USER_ID-}" && -n "${GROUP_NAME-}" && -n "${GROUP_ID-}" ]]; then
    getent group ${GROUP_NAME} > /dev/null 2>&1 || groupadd -g ${GROUP_ID} ${GROUP_NAME}
    getent passwd ${USER_NAME} > /dev/null 2>&1 || useradd -u ${USER_ID} -g ${GROUP_NAME} -G supergroup -M ${USER_NAME}
fi

sed -i "/<\/configuration>/i \  <property>\n    <name>yarn.app.mapreduce.am.job.client.port-range</name>\n    <value>${AM_RPC}</value>\n  </property>" "$HADOOP_CONF_DIR/mapred-site.xml"

wait_until_service_up "${HADOOP_MASTER}" "9870" || exit 1
gosu hdfs bash -lc "${HADOOP_HOME}/bin/hdfs --daemon start datanode"
wait_until_service_up "$HOSTNAME" "9864" || exit 1

wait_until_service_up "${HADOOP_MASTER}" "8088" || exit 1
gosu yarn bash -lc "${HADOOP_HOME}/bin/yarn --daemon start nodemanager"
wait_until_service_up "$HOSTNAME" "8042" || exit 1

echo "Hadoop worker services started: DataNode (hdfs), NodeManager (yarn)."

trap '
    echo "Stopping Hadoop worker..."; \
    gosu yarn bash -lc "${HADOOP_HOME}/bin/yarn --daemon stop nodemanager" || true; \
    gosu hdfs bash -lc "${HADOOP_HOME}/bin/hdfs --daemon stop datanode" || true; \
    exit 0 \
    ' SIGTERM SIGINT

tail -f /dev/null & wait $!

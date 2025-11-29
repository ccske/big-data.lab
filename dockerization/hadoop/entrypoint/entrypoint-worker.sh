#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
source "${SCRIPT_DIR}/common.sh"

JAVA_HOME="$(dirname "$(dirname "$(readlink -f "$(which java)")")")"

sed -i "/<\/configuration>/i \  <property>\n    <name>yarn.app.mapreduce.am.job.client.port-range</name>\n    <value>${AM_RPC}</value>\n  </property>" "$HADOOP_CONF_DIR/mapred-site.xml"

wait_until_service_up "${HADOOP_MASTER_HOSTNAME}" "9870" || exit 1
gosu hdfs bash -lc "${HADOOP_HOME}/bin/hdfs --daemon start datanode"
wait_until_service_up "${HOSTNAME}" "9864" || exit 1

wait_until_service_up "${HADOOP_MASTER_HOSTNAME}" "8088" || exit 1
gosu yarn bash -lc "${HADOOP_HOME}/bin/yarn --daemon start nodemanager"
wait_until_service_up "${HOSTNAME}" "8042" || exit 1

echo "Hadoop Worker Services started: DataNode (hdfs), NodeManager (yarn)."

trap '
    echo "Stopping Hadoop Worker..."; \
    gosu yarn bash -lc "${HADOOP_HOME}/bin/yarn --daemon stop nodemanager" || true; \
    gosu hdfs bash -lc "${HADOOP_HOME}/bin/hdfs --daemon stop datanode" || true; \
    exit 0 \
    ' SIGTERM SIGINT

tail -f /dev/null & wait $!

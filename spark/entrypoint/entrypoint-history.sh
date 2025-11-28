#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
source "${SCRIPT_DIR}/common.sh"

JAVA_HOME="$(dirname "$(dirname "$(readlink -f "$(which java)")")")"

wait_until_service_up "${HADOOP_MASTER_HOSTNAME}" "9870" || exit 1  # HDFS NameNode UI
wait_until_service_up "${HADOOP_MASTER_HOSTNAME}" "8088" || exit 1  # YARN ResourceManager UI

gosu hdfs bash -lc "/opt/hadoop/bin/hdfs dfs -ls /spark-logs >/dev/null 2>&1 || ( /opt/hadoop/bin/hdfs dfs -mkdir -p /spark-logs && /opt/hadoop/bin/hdfs dfs -chmod 1777 /spark-logs )"
gosu hdfs bash -lc "/opt/hadoop/bin/hdfs dfs -ls /spark-dist >/dev/null 2>&1 || ( /opt/hadoop/bin/hdfs dfs -mkdir -p /spark-dist && /opt/hadoop/bin/hdfs dfs -chmod 1777 /spark-dist )"
gosu spark bash -lc "/opt/hadoop/bin/hdfs dfs -ls /spark-dist/jars >/dev/null 2>&1 || /opt/hadoop/bin/hdfs dfs -put ${SPARK_HOME}/jars /spark-dist/"

gosu spark bash -lc "${SPARK_HOME}/sbin/start-history-server.sh"
wait_until_service_up "${HOSTNAME}" "18080" || exit 1

echo "Spark History Server (spark) started at http://${HOSTNAME}:18080"

trap '
    echo "Stopping Spark History Server..."; \
    gosu spark bash -lc "${SPARK_HOME}/sbin/stop-history-server.sh" || true; \
    exit 0 \
    ' SIGTERM SIGINT

tail -f /dev/null & wait $!

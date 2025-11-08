#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
source "${SCRIPT_DIR}/common.sh"

JAVA_HOME="$(dirname "$(dirname "$(readlink -f "$(which java)")")")"

wait_until_service_up "mysql" "3306" || exit 1
wait_until_service_up "hadoop-master" "9870" || exit 1

gosu hive bash -lc \
    "${HADOOP_HOME}/bin/hdfs dfs -ls /user/hive 2> /dev/null || \
    ( ${HADOOP_HOME}/bin/hdfs dfs -mkdir -p /user/hive/warehouse && ${HADOOP_HOME}/bin/hdfs dfs -chmod -R 775 /user/hive/warehouse )"

if ! "${HIVE_HOME}/bin/schematool" -dbType mysql -validate > /dev/null 2>&1; then
    echo "Initializing Hive metastore schema..."
    "${HIVE_HOME}/bin/schematool" -dbType mysql -initSchema
else
    echo "Metastore schema already initialized; skipping."
fi

METASTORE_LOG="${HIVE_LOG_DIR}/metastore.log"
gosu hive bash -lc \
      "nohup ${HIVE_HOME}/bin/hive --service metastore > '${METASTORE_LOG}' 2>&1 & echo \$! > ${HIVE_PID_DIR}/metastore.pid"

METASTORE_PID="$(cat ${HIVE_PID_DIR}/metastore.pid)"
wait_until_service_up "localhost" "9083" || { echo "Metastore failed to come up"; kill -TERM "${METASTORE_PID}" || true; exit 1; }

echo "Hive Metastore started (pid=${METASTORE_PID})."

trap '
	echo "Stopping Hive Metastore..."
    if [[ -f ${HIVE_PID_DIR}/metastore.pid ]]; then
    	kill -TERM "$(cat ${HIVE_PID_DIR}/metastore.pid)" || true
    	wait "$(cat ${HIVE_PID_DIR}/metastore.pid)" 2> /dev/null || true
    	rm -f ${HIVE_PID_DIR}/metastore.pid
  	fi
  	exit 0
	' SIGTERM SIGINT

tail -f /dev/null & wait $!

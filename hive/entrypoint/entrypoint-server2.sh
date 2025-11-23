#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
source "${SCRIPT_DIR}/common.sh"

JAVA_HOME="$(dirname "$(dirname "$(readlink -f "$(which java)")")")"

wait_until_service_up "${HADOOP_MASTER}" "9870" || exit 1
wait_until_service_up "${HADOOP_MASTER}" "8088" || exit 1
wait_until_service_up "${HIVE_METASTORE}" "9083" || exit 1

HS2_LOG="${HIVE_LOG_DIR}/hiveserver2.log"
gosu hive bash -lc "nohup ${HIVE_HOME}/bin/hive --service hiveserver2 > '${HS2_LOG}' 2>&1 &"
wait_until_file_created "${HIVESERVER2_PID_DIR:-$HIVE_PID_DIR}/hiveserver2.pid"
HS2_PID="$(cat ${HIVESERVER2_PID_DIR:-$HIVE_PID_DIR}/hiveserver2.pid 2>/dev/null || true)"

wait_until_service_up "$HOSTNAME" "10000" || { echo "HS2 Thrift failed"; kill -TERM "${HS2_PID}" || true; exit 1; }
wait_until_service_up "$HOSTNAME" "10002" || { echo "HS2 UI failed"; kill -TERM "${HS2_PID}" || true; exit 1; }

echo "HiveServer2 started (pid=${HS2_PID})."

trap '
	echo "Stopping HiveServer2..."
    if [[ -f ${HIVESERVER2_PID_DIR:-$HIVE_PID_DIR}/hiveserver2.pid ]]; then
        kill -TERM "$(cat ${HIVESERVER2_PID_DIR:-$HIVE_PID_DIR}/hiveserver2.pid)" || true
    	wait "$(cat ${HIVE_PID_DIR}/hiveserver2.pid)" 2>/dev/null || true
        rm -f ${HIVESERVER2_PID_DIR:-$HIVE_PID_DIR}/hiveserver2.pid
  	fi
  	exit 0
	' SIGTERM SIGINT

tail -f /dev/null & wait $!

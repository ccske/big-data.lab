#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
source "${SCRIPT_DIR}/common.sh"

JAVA_HOME="$(dirname "$(dirname "$(readlink -f "$(which java)")")")"

CLUSTER_ID=$($KAFKA_HOME/bin/kafka-storage.sh random-uuid)
CONF_FILE="${KAFKA_CONF_DIR}/kraft/server.properties"

if [[ ! -f "${KAFKA_DATA_DIR}/meta.properties" ]]; then
    echo "Formatting Kafka storage..."
    gosu kafka bash -lc "${KAFKA_HOME}/bin/kafka-storage.sh format --config \"${CONF_FILE}\" --cluster-id ${CLUSTER_ID} --ignore-formatted"
fi

gosu kafka bash -lc "${KAFKA_HOME}/bin/kafka-server-start.sh \"${CONF_FILE}\"" &
wait_until_service_up "${HOSTNAME}" "9092" || exit 1

echo "Kafka started on PLAINTEXT://$HOSTNAME:9092"


trap '
    echo "Stopping Kafka..."; \
    gosu kafka bash -lc "${KAFKA_HOME}/bin/kafka-server-stop.sh" || true; \
    exit 0 \
    ' SIGTERM SIGINT

tail -f /dev/null & wait $!

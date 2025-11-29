# shellcheck shell=bash

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    echo "This file is a library and must be sourced, not executed." >&2
    exit 1
fi

if [[ -n "${_COMMON_SH_INCLUDED:-}" ]]; then
    return 0
fi
readonly _COMMON_SH_INCLUDED=1

function wait_until_service_up() {
    local host=$1
    local port=$2
    local timeout=180
    local sleep_interval=3
    local start_time=$(date +%s)
    local current_time=${start_time}

    (( timeout_time = start_time + timeout ))
    while (( current_time <= timeout_time )); do
        nc -z $host $port
        if [[ $? -eq 0 ]]; then
            break
        fi
        sleep ${sleep_interval}
        current_time=$(date +%s)
        (( elapsed = current_time - start_time ))
        echo "[$elapsed/$timeout] waiting for $host:$port..."
    done

    if (( current_time > timeout_time )); then
        echo "$host:$port is still down!"
        return 1
    fi

    echo "$host:$port is up."
    return 0
}

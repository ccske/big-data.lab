#!/usr/bin/env bash

set -euo pipefail

# Make sure the system is supported
if [[ -r /etc/os-release ]]; then
    source /etc/os-release
fi
if [[ "$ID" != "ubuntu" ]]; then
    echo "Error: Only Ubuntu Linux supported"
    exit 1
fi

# System variables
ARCH=$(dpkg --print-architecture)
PROJECT_DIR=$(realpath "$(dirname "$0")")
USER_NAME=$(id -un)
USER_ID=$(id -u)
GROUP_NAME=$(id -gn)
GROUP_ID=$(id -g)

# Add current user into no-password sudoer list
NP_SUDOERS=/etc/sudoers.d/nopasswd
NP_ENTRY="${USER_NAME} ALL=(ALL) NOPASSWD: ALL"
if [[ ! -f "${NP_SUDOERS}" ]]; then
    sudo touch "${NP_SUDOERS}" && sudo chmod 0400 "${NP_SUDOERS}"
fi
if ! sudo grep -qxF "${NP_ENTRY}" "${NP_SUDOERS}"; then
    echo "${NP_ENTRY}" | sudo tee -a "${NP_SUDOERS}" > /dev/null
fi

# Keep APT packages up-to-date
sudo DEBIAN_FRONTEND=noninteractive apt-get update && sudo DEBIAN_FRONTEND=noninteractive apt-get upgrade -y
if [[ $? -ne 0 ]]; then
    echo "Error: Package repositories could be temporarily unavailable. Pleast try again later."
    exit 1
fi

# Install latest Docker and Compose
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
APT_DOCKER_ASC=/etc/apt/keyrings/docker.asc
APT_DOCKER_LIST=/etc/apt/sources.list.d/docker.list
APT_DOCKER_URL=https://download.docker.com/linux/ubuntu
sudo curl -fsSL ${APT_DOCKER_URL}/gpg -o ${APT_DOCKER_ASC} && sudo chmod a+r ${APT_DOCKER_ASC}
if [[ ! -f "${APT_DOCKER_LIST}" ]]; then
    echo "deb [arch=$ARCH signed-by=${APT_DOCKER_ASC}] ${APT_DOCKER_URL} ${UBUNTU_CODENAME:-$VERSION_CODENAME} stable" | \
        sudo tee ${APT_DOCKER_LIST} > /dev/null
fi
sudo DEBIAN_FRONTEND=noninteractive apt-get update
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo usermod -aG docker ${USER_NAME}

# Build and launch Hadoop ecosystem containers via Docker Compose
printf "USER_NAME=%s\nUSER_ID=%s\nGROUP_NAME=%s\nGROUP_ID=%s\n" \
    "${USER_NAME}" "${USER_ID}" "${GROUP_NAME}" "${GROUP_ID}" | \
    tee "${PROJECT_DIR}/.env" > /dev/null
sg docker -c "docker compose --project-directory ${PROJECT_DIR} up --build -d"
HOSTS_ENTRY="127.0.0.1 hadoop-master hadoop-worker1 hadoop-worker2 hadoop-worker3"
if ! grep -qxF "${HOSTS_ENTRY}" "/etc/hosts"; then
    echo | sudo tee -a "/etc/hosts" > /dev/null
    echo "${HOSTS_ENTRY}" | sudo tee -a "/etc/hosts" > /dev/null
fi

# Set up Java environment
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y openjdk-11-jdk
JAVA_HOME="$(dirname "$(dirname "$(readlink -f "$(which java)")")")"
JAVA_HOME_ENTRY="export JAVA_HOME=${JAVA_HOME}"
if ! grep -qxF "${JAVA_HOME_ENTRY}" "$HOME/.bashrc"; then
    echo | tee -a "$HOME/.bashrc" > /dev/null
    echo "${JAVA_HOME_ENTRY}" | tee -a "$HOME/.bashrc" > /dev/null
fi

# Set up as Hadoop client
HADOOP_HOME="/opt/hadoop"
if [[ ! -d ${HADOOP_HOME} ]]; then
    sudo docker cp -aL hadoop-master:${HADOOP_HOME} $(realpath "$(dirname "${HADOOP_HOME}")")
fi
HADOOP_BIN="${HADOOP_HOME}/bin"
if [[ ":$PATH:" != *":${HADOOP_BIN}:"* ]]; then
    echo | tee -a "$HOME/.bashrc" > /dev/null
    printf "%s\n%s\n%s\n" \
        "if [[ \":\$PATH:\" != *\":${HADOOP_BIN}:\"* ]]; then" \
        "    export PATH=\"${HADOOP_BIN}:\$PATH\"" \
        "fi" | \
        tee -a "$HOME/.bashrc" > /dev/null
fi

# Install commonly used tools (optional)
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y net-tools ssh tmux vim

# Done
echo "-------------------------------------------------------------------------------------"
echo ">>> Successfully set up big-data.lab! You may reboot the system to apply all changes."
echo

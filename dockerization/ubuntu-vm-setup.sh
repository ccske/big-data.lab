#!/usr/bin/env bash

set -euo pipefail

# Make sure the system is supported
if [[ -r "/etc/os-release" ]]; then
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
sudo curl -fkSL ${APT_DOCKER_URL}/gpg -o ${APT_DOCKER_ASC} && sudo chmod +r ${APT_DOCKER_ASC}
if [[ ! -f "${APT_DOCKER_LIST}" ]]; then
    echo "deb [arch=$ARCH signed-by=${APT_DOCKER_ASC}] ${APT_DOCKER_URL} ${UBUNTU_CODENAME:-$VERSION_CODENAME} stable" | \
        sudo tee ${APT_DOCKER_LIST} > /dev/null
fi
sudo DEBIAN_FRONTEND=noninteractive apt-get update
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo usermod -aG docker ${USER_NAME}


# Pre-download Apache tarballs
COMPONENTS=("HADOOP" "SPARK" "PIG" "KAFKA")
HADOOP_VERSION=3.4.0
SPARK_VERSION=3.5.7
PIG_VERSION=0.18.0
KAFKA_VERSION=3.9.1
SCALA_VERSION=2.12
case "${ARCH:-unknown}" in
  amd64)
      HADOOP_TGZ="hadoop-${HADOOP_VERSION}.tar.gz"
      SPARK_TGZ="spark-${SPARK_VERSION}-bin-hadoop3.tgz"
      PIG_TGZ="pig-${PIG_VERSION}.tar.gz"
      KAFKA_TGZ="kafka_${SCALA_VERSION}-${KAFKA_VERSION}.tgz"
      ;;
  arm64)
      HADOOP_TGZ="hadoop-${HADOOP_VERSION}-aarch64.tar.gz"
      SPARK_TGZ="spark-${SPARK_VERSION}-bin-hadoop3.tgz"
      PIG_TGZ="pig-${PIG_VERSION}.tar.gz"
      KAFKA_TGZ="kafka_${SCALA_VERSION}-${KAFKA_VERSION}.tgz"
      ;;
  *)
      echo "Unsupported arch: $ARCH"
      exit 1
      ;;
esac
HADOOP_URL="https://archive.apache.org/dist/hadoop/common/hadoop-${HADOOP_VERSION}/${HADOOP_TGZ}"
SPARK_URL="https://archive.apache.org/dist/spark/spark-${SPARK_VERSION}/${SPARK_TGZ}"
PIG_URL="https://archive.apache.org/dist/pig/pig-${PIG_VERSION}/${PIG_TGZ}"
KAFKA_URL="https://archive.apache.org/dist/kafka/${KAFKA_VERSION}/${KAFKA_TGZ}"

TARBALL_DIR="${PROJECT_DIR}/tarball"
[[ -d "${TARBALL_DIR}" ]] || mkdir -p "${TARBALL_DIR}"
for COMPONENT in "${COMPONENTS[@]}"; do
    TGZ="${COMPONENT}_TGZ"
    URL="${COMPONENT}_URL"
    if [[ ! -f "${TARBALL_DIR}/${!TGZ}" ]]; then
        ( set -x; curl -fkSL "${!URL}" -o "${TARBALL_DIR}/${!TGZ}" )
    fi
done


# Build and launch Hadoop ecosystem containers via Docker Compose
if [[ ! -f "${PROJECT_DIR}/.env" ]]; then
    touch "${PROJECT_DIR}/.env"
    for COMPONENT in "${COMPONENTS[@]}"; do
        VERSION="${COMPONENT}_VERSION"
        echo "${VERSION}=${!VERSION}" | tee -a "${PROJECT_DIR}/.env" > /dev/null
    done
    echo "SCALA_VERSION=${SCALA_VERSION}" | tee -a "${PROJECT_DIR}/.env" > /dev/null
    printf "USER_NAME=%s\nUSER_ID=%s\nGROUP_NAME=%s\nGROUP_ID=%s\n" \
        "${USER_NAME}" "${USER_ID}" "${GROUP_NAME}" "${GROUP_ID}" | \
        tee -a "${PROJECT_DIR}/.env" > /dev/null
fi

sg docker -c "docker compose --project-directory ${PROJECT_DIR} up --build -d"
HOSTS_ENTRY="127.0.0.1 hadoop-master hadoop-worker1 hadoop-worker2 hadoop-worker3 spark-history kafka"
if ! grep -qxF "${HOSTS_ENTRY}" "/etc/hosts"; then
    echo | sudo tee -a "/etc/hosts" > /dev/null
    echo "${HOSTS_ENTRY}" | sudo tee -a "/etc/hosts" > /dev/null
fi

BIG_DATA_LAB_ENV=".big-data.lab.env"
truncate -s 0 "${PROJECT_DIR}/${BIG_DATA_LAB_ENV}"


# Set up Java environment
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y openjdk-11-jdk
JAVA_HOME="$(dirname "$(dirname "$(readlink -f "$(which java)")")")"
echo "export JAVA_HOME=\"${JAVA_HOME}\"" | tee -a "${PROJECT_DIR}/${BIG_DATA_LAB_ENV}" > /dev/null


# Set up client environment
HADOOP_HOME="/opt/hadoop"
echo "Set up Hadoop environment"
if [[ ! -d "${HADOOP_HOME}" ]]; then
    sudo docker cp -aL hadoop-master:${HADOOP_HOME} $(realpath "$(dirname "${HADOOP_HOME}")")
fi
echo | tee -a "${PROJECT_DIR}/${BIG_DATA_LAB_ENV}" > /dev/null
echo "export HADOOP_HOME=\"${HADOOP_HOME}\"" | tee -a "${PROJECT_DIR}/${BIG_DATA_LAB_ENV}" > /dev/null
echo "export HADOOP_CONF_DIR=\"${HADOOP_HOME}/etc/hadoop\"" | tee -a "${PROJECT_DIR}/${BIG_DATA_LAB_ENV}" > /dev/null
echo "export LD_LIBRARY_PATH=\"${HADOOP_HOME}/lib/native:${LD_LIBRARY_PATH:-}\"" | tee -a "${PROJECT_DIR}/${BIG_DATA_LAB_ENV}" > /dev/null

SPARK_HOME="/opt/spark"
echo "Set up Spark environment"
if [[ ! -d "${SPARK_HOME}" ]]; then
    sudo docker cp -aL spark-history:${SPARK_HOME} $(realpath "$(dirname "${SPARK_HOME}")")
fi
echo | tee -a "${PROJECT_DIR}/${BIG_DATA_LAB_ENV}" > /dev/null
echo "export SPARK_HOME=\"${SPARK_HOME}\"" | tee -a "${PROJECT_DIR}/${BIG_DATA_LAB_ENV}" > /dev/null
echo "export SPARK_CONF_DIR=\"${SPARK_HOME}/conf\"" | tee -a "${PROJECT_DIR}/${BIG_DATA_LAB_ENV}" > /dev/null
echo "export SPARK_LOCAL_IP=\"$(hostname -I | awk '{print $1}')\"" | tee -a "${PROJECT_DIR}/${BIG_DATA_LAB_ENV}" > /dev/null

PIG_HOME="/opt/pig"
echo "Set up Pig environment"
if [[ ! -d "${PIG_HOME}" && ! ( -L "${PIG_HOME}" && -d "$(readlink -f -- "${PIG_HOME}")" ) ]]; then
    sudo tar -xzf "${TARBALL_DIR}/${PIG_TGZ}" -C /opt
    sudo ln -s pig-${PIG_VERSION} ${PIG_HOME}
    sudo sed -i 's/^pig\.ats\.enabled=true/pig.ats.enabled=false/' "${PIG_HOME}/conf/pig.properties"
fi
echo | tee -a "${PROJECT_DIR}/${BIG_DATA_LAB_ENV}" > /dev/null
echo "export PIG_HOME=\"${PIG_HOME}\"" | tee -a "${PROJECT_DIR}/${BIG_DATA_LAB_ENV}" > /dev/null
echo "export PIG_CONF_DIR=\"${PIG_HOME}/conf\"" | tee -a "${PROJECT_DIR}/${BIG_DATA_LAB_ENV}" > /dev/null

KAFKA_HOME="/opt/kafka"
echo "Set up Kafka environment"
if [[ ! -d "${KAFKA_HOME}" ]]; then
    sudo docker cp -aL kafka:${KAFKA_HOME} $(realpath "$(dirname "${KAFKA_HOME}")")
fi
echo | tee -a "${PROJECT_DIR}/${BIG_DATA_LAB_ENV}" > /dev/null
echo "export KAFKA_HOME=\"${KAFKA_HOME}\"" | tee -a "${PROJECT_DIR}/${BIG_DATA_LAB_ENV}" > /dev/null
echo "export KAFKA_CONF_DIR=\"${KAFKA_HOME}/config\"" | tee -a "${PROJECT_DIR}/${BIG_DATA_LAB_ENV}" > /dev/null

BIG_DATA_LAB_BIN="${HADOOP_HOME}/bin:${SPARK_HOME}/bin:${PIG_HOME}/bin:${KAFKA_HOME}/bin"
echo | tee -a "${PROJECT_DIR}/${BIG_DATA_LAB_ENV}" > /dev/null
printf "%s\n%s\n%s\n" \
    "if [[ \":\$PATH:\" != *\":${BIG_DATA_LAB_BIN}:\"* ]]; then" \
    "    export PATH=\"${BIG_DATA_LAB_BIN}:\$PATH\"" \
    "fi" | \
    tee -a "${PROJECT_DIR}/${BIG_DATA_LAB_ENV}" > /dev/null

cp -f "${PROJECT_DIR}/${BIG_DATA_LAB_ENV}" "$HOME/"
if ! grep -qxF "    . ~/${BIG_DATA_LAB_ENV}" "$HOME/.bashrc"; then
    printf "\n%s\n%s\n%s\n" \
        "if [ -f ~/${BIG_DATA_LAB_ENV} ]; then" \
        "    . ~/${BIG_DATA_LAB_ENV}" \
        "fi" | \
        tee -a "$HOME/.bashrc" > /dev/null
fi

source ~/${BIG_DATA_LAB_ENV}

sudo DEBIAN_FRONTEND=noninteractive apt-get install -y mysql-client
MYSQL_CLIENT_CNF=".my.cnf"
if [[ ! -f "$HOME/${MYSQL_CLIENT_CNF}" ]]; then
    cp -f "${PROJECT_DIR}/mysql/client/${MYSQL_CLIENT_CNF}" "$HOME/"
fi


# Install commonly used tools (optional)
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y net-tools ssh tmux vim


# Done
echo
echo ">>> Set up big-data.lab successfully! You may reboot the system to apply all changes."
echo

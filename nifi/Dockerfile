FROM apache/nifi:2.6.0

ENV NIFI_HOME=/opt/nifi/nifi-current
ENV NIFI_NAR_EXTENSIONS_DIR=${NIFI_HOME}/nar_extensions
ENV NIFI_WEB_HTTPS_PORT=8443
ENV SINGLE_USER_CREDENTIALS_USERNAME=nifi
ENV SINGLE_USER_CREDENTIALS_PASSWORD=nifi12345678
ENV HADOOP_HOME=/opt/hadoop
ENV HADOOP_CONF_DIR=${HADOOP_HOME}/etc/hadoop

ARG MYSQL_CONNECTOR_J_VERSION=8.4.0
RUN set -eux && \
    curl -fkSL "https://downloads.mysql.com/archives/get/p/3/file/mysql-connector-j-${MYSQL_CONNECTOR_J_VERSION}.tar.gz" | tar -xz -C /tmp && \
    cp -f /tmp/mysql-connector-j-${MYSQL_CONNECTOR_J_VERSION}/mysql-connector-j-${MYSQL_CONNECTOR_J_VERSION}.jar ${NIFI_HOME}/lib/ && \
    ln -s mysql-connector-j-${MYSQL_CONNECTOR_J_VERSION}.jar ${NIFI_HOME}/lib/mysql-connector-java.jar && \
    rm -rf /tmp/mysql-connector-j-${MYSQL_CONNECTOR_J_VERSION}

ARG NIFI_VERSION=2.6.0
RUN set -eux && \
    NIFI_HADOOP_NAR="nifi-hadoop-nar-${NIFI_VERSION}.nar" && \
    curl -fkSL "https://repo1.maven.org/maven2/org/apache/nifi/nifi-hadoop-nar/${NIFI_VERSION}/${NIFI_HADOOP_NAR}" -o "${NIFI_NAR_EXTENSIONS_DIR}/${NIFI_HADOOP_NAR}" && \
    NIFI_HADOOP_LIBRARIES_NAR="nifi-hadoop-libraries-nar-${NIFI_VERSION}.nar" && \
    curl -fkSL "https://repo1.maven.org/maven2/org/apache/nifi/nifi-hadoop-libraries-nar/${NIFI_VERSION}/${NIFI_HADOOP_LIBRARIES_NAR}" -o "${NIFI_NAR_EXTENSIONS_DIR}/${NIFI_HADOOP_LIBRARIES_NAR}"

USER root
COPY hadoop/etc/hadoop/* ${HADOOP_CONF_DIR}/
USER nifi

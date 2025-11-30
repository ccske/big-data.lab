#!/usr/bin/env bash

set -e

export HADOOP_HOME=/opt/hadoop

sudo -u mapred ${HADOOP_HOME}/bin/mapred --daemon stop historyserver
sudo -u yarn ${HADOOP_HOME}/bin/yarn --daemon stop nodemanager
sudo -u yarn ${HADOOP_HOME}/bin/yarn --daemon stop resourcemanager
sudo -u hdfs ${HADOOP_HOME}/bin/hdfs --daemon stop datanode
sudo -u hdfs ${HADOOP_HOME}/bin/hdfs --daemon stop namenode

#!/usr/bin/env bash

set -e

export HADOOP_HOME=/opt/hadoop

sudo -u hdfs ${HADOOP_HOME}/bin/hdfs --daemon start namenode
sudo -u hdfs ${HADOOP_HOME}/bin/hdfs --daemon start datanode
sudo -u yarn ${HADOOP_HOME}/bin/yarn --daemon start resourcemanager
sudo -u yarn ${HADOOP_HOME}/bin/yarn --daemon start nodemanager
sudo -u mapred ${HADOOP_HOME}/bin/mapred --daemon start historyserver

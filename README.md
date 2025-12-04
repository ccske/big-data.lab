# big-data.lab

A lightweight Hadoop ecosystem on Ubuntu Linux virtual machine for educational and research purposes.

This project now includes Hadoop, Spark, Pig, Kafka, and MySQL components, providing a complete big data lab environment for classroom teaching and student practice.

It is designed for **teachers and students** as an educational tool, while **universities and institutions** can obtain commercial licenses for classroom or production use.

---

## Features
- **Hadoop 3.4.0** (HDFS, YARN, MapReduce, JobHistoryServer)
- **Spark 3.5.7** (YARN client mode, History Server)
- **Pig 0.18.0**
- **Kafka 3.9.1** (KRaft mode)
- Automated setup script: `ubuntu-vm-setup.sh` installs and configures all components.

---

## Project Structure
```
big-data.lab
├── COMMERCIAL_LICENSE.md
├── CONTRIBUTING.md
├── hadoop
│   ├── etc
│   │   └── hadoop
│   │       ├── capacity-scheduler.xml
│   │       ├── core-site.xml
│   │       ├── hadoop-env.sh
│   │       ├── hdfs-site.xml
│   │       ├── mapred-site.xml
│   │       └── yarn-site.xml
│   ├── sbin
│   │   ├── start-hadoop.sh
│   │   └── stop-hadoop.sh
│   └── systemd
│       └── hadoop.service
├── kafka
│   ├── config
│   │   └── kraft
│   │       └── server.properties
│   └── systemd
│       └── kafka.service
├── LICENSE-AGPL
├── LICENSE.md
├── pig
│   └── conf
│       └── pig.properties
├── README.md
├── spark
│   ├── conf
│   │   ├── spark-defaults.conf
│   │   └── spark-env.sh
│   └── systemd
│       └── spark-historyserver.service
└── ubuntu-vm-setup.sh
```

---

## Quick Setup on Ubuntu Virtual Machine

The system relies on `ubuntu-vm-setup.sh` to automate everything. Follow these steps:

### Prerequisites
- Ubuntu Linux 24.04+ virtual machine (2+ CPUs and 4+ GB RAM)
- Internet access for downloading packages and Apache tarballs

### Steps
1. Download or clone this repository:
   ```bash
   git clone https://github.com/your-org/big-data.lab.git
   cd big-data.lab
   ```

2. Run the setup script:
   ```bash
   ./ubuntu-vm-setup.sh
   ```

3. **Reboot the VM** after the script completes to apply all changes.

4. After reboot, the Hadoop ecosystem will be running in the background. Access the web UIs from the VM browser:
   - **HDFS NameNode**: http://localhost:9870
   - **YARN ResourceManager**: http://localhost:8088
   - **MapReduce JobHistory**: http://localhost:19888
   - **Spark History Server**: http://localhost:18080

To access UIs from outside the VM, add this to your system hosts file:
```
<VM_IP> <VM_HOSTNAME>
```
Replace `<VM_IP>` and `<VM_HOSTNAME>` with the IP address and the hostname of your VM respectively. For example:
```
192.168.64.7 u24arm64
```

---

## Service Management
- Hadoop: `systemctl start|stop|restart hadoop.service`
- Spark History Server: `systemctl start|stop|restart spark-historyserver.service`
- Kafka: `systemctl start|stop|restart kafka.service`

## Big Data Client Usage
After setup, you can use multiple tools provided by the ecosystem. Ensure you have sourced the environment file (`.big-data.lab.env`) created by the setup script.

#### Hadoop
```bash
hdfs dfs -ls /
hdfs dfs -mkdir /data
hdfs dfs -put localfile.txt /data
hdfs dfs -cat /data/localfile.txt
```

#### Spark
Submit a Spark job to YARN:
```bash
${SPARK_HOME}/bin/spark-shell --master yarn
${SPARK_HOME}/bin/spark-submit --master yarn --deploy-mode client examples/src/main/python/pi.py 10
```

#### Pig
Run a Pig script:
```bash
pig -x mapreduce
-- Example Pig script
A = LOAD '/data/localfile.txt' USING PigStorage() AS (line:chararray);
DUMP A;
```

#### Kafka
Create a topic and send messages:
```bash
# Create topic
${KAFKA_HOME}/bin/kafka-topics.sh --create --topic test --bootstrap-server kafka:9092 --partitions 1 --replication-factor 1

# List topics
${KAFKA_HOME}/bin/kafka-topics.sh --list --bootstrap-server kafka:9092

# Produce messages
${KAFKA_HOME}/bin/kafka-console-producer.sh --broker-list kafka:9092 --topic test

# Consume messages
${KAFKA_HOME}/bin/kafka-console-consumer.sh --bootstrap-server kafka:9092 --topic test --from-beginning
```

---

## License
This project uses a **dual-licensing model**:

1. **AGPL v3 License (Free / Open Source)**  
   - Free for personal learning, academic research, and non-commercial use.  
   - Users of this version must comply with AGPL v3 obligations.  
   - See [LICENSE.md](LICENSE.md) and [LICENSE-AGPL](LICENSE-AGPL) for details.

2. **Commercial License**  
   - Required for commercial use, institutional deployment, or to avoid AGPL copyleft obligations.  
   - See [COMMERCIAL_LICENSE.md](COMMERCIAL_LICENSE.md) for details.  
   - Contact Christopher Ke at christopher.cske@gmail.com for inquiries.

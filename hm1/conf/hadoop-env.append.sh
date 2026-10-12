# BEGIN hdfs-cluster
export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64
export HADOOP_HOME=/opt/hadoop
export HADOOP_CONF_DIR="${HADOOP_HOME}/etc/hadoop"
export HADOOP_LOG_DIR=/var/log/hadoop
export HADOOP_PID_DIR=/var/lib/hadoop/pids
export HDFS_NAMENODE_USER=hdfs
export HDFS_DATANODE_USER=hdfs
export HDFS_SECONDARYNAMENODE_USER=hdfs
export HDFS_NAMENODE_OPTS="-Xmx1024m"
export HDFS_DATANODE_OPTS="-Xmx512m"
export HDFS_SECONDARYNAMENODE_OPTS="-Xmx512m"
export HADOOP_SSH_OPTS="-o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=15 -o ServerAliveInterval=15"
# END hdfs-cluster

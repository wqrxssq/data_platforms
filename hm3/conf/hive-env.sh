export HADOOP_HOME=/opt/hadoop
export HIVE_CONF_DIR=/opt/hive/conf

if [ "$SERVICE" = "metastore" ]; then
  export HADOOP_HEAPSIZE=512
elif [ "$SERVICE" = "hiveserver2" ]; then
  export HADOOP_HEAPSIZE=1024
else
  export HADOOP_HEAPSIZE=256
fi

# Hadoop на кластере работает на Java 17, Hive 4.0.0-alpha-2 рассчитан на Java 8
# и обращается к закрытым модулям JDK через reflection
JAVA17_OPENS="--add-opens=java.base/java.lang=ALL-UNNAMED --add-opens=java.base/java.lang.reflect=ALL-UNNAMED --add-opens=java.base/java.io=ALL-UNNAMED --add-opens=java.base/java.net=ALL-UNNAMED --add-opens=java.base/java.nio=ALL-UNNAMED --add-opens=java.base/java.util=ALL-UNNAMED --add-opens=java.base/java.util.concurrent=ALL-UNNAMED --add-opens=java.base/java.util.concurrent.atomic=ALL-UNNAMED --add-opens=java.base/java.util.regex=ALL-UNNAMED --add-opens=java.base/java.time=ALL-UNNAMED --add-opens=java.base/sun.nio.ch=ALL-UNNAMED --add-opens=java.sql/java.sql=ALL-UNNAMED"
export HADOOP_CLIENT_OPTS="$HADOOP_CLIENT_OPTS $JAVA17_OPENS"

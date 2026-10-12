# Кластер HDFS

HDFS 3.4.3: NameNode, Secondary NameNode и три DataNode. Запуск с `team-23-en` от пользователя `team`.

| Узел | Сервисы |
|---|---|
| `team-23-nn` | NameNode |
| `team-23-en` | Secondary NameNode, DataNode |
| `team-23-00` | DataNode |
| `team-23-01` | DataNode |

Процессы запускаются от пользователя `hdfs`. Java — OpenJDK 17, каталог Hadoop — `/opt/hadoop`.

## Команды

Из корня репозитория на `team-23-en`:

```bash
./scripts/deploy.sh   # установка, конфигурация, формат и запуск
./scripts/start.sh    # start-dfs.sh
./scripts/stop.sh     # stop-dfs.sh
./scripts/verify.sh   # проверка уже запущенного кластера
```

## Установка

На каждом узле.

```bash
sudo apt-get update
sudo apt-get install -y openjdk-17-jdk-headless
sudo useradd --create-home --shell /bin/bash --user-group hdfs
sudo mkdir -p /var/lib/hadoop/{namenode,datanode,namesecondary,tmp,pids} /var/log/hadoop
sudo chown -R hdfs:hdfs /var/lib/hadoop /var/log/hadoop
```

Дистрибутив: <https://dlcdn.apache.org/hadoop/common/hadoop-3.4.3/hadoop-3.4.3.tar.gz>

Контрольная сумма: <https://downloads.apache.org/hadoop/common/hadoop-3.4.3/hadoop-3.4.3.tar.gz.sha512>

```bash
sha512sum hadoop-3.4.3.tar.gz
sudo tar -C /opt -xzf hadoop-3.4.3.tar.gz
sudo ln -sfn /opt/hadoop-3.4.3 /opt/hadoop
sudo chown -R hdfs:hdfs /opt/hadoop-3.4.3
```

`/etc/profile.d/hadoop.sh` (`conf/hadoop.sh`):

```bash
export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64
export HADOOP_HOME=/opt/hadoop
export HADOOP_CONF_DIR="${HADOOP_HOME}/etc/hadoop"
export PATH="${JAVA_HOME}/bin:${HADOOP_HOME}/bin:${HADOOP_HOME}/sbin:${PATH}"
```

В конец `/opt/hadoop/etc/hadoop/hadoop-env.sh` дописать `conf/hadoop-env.append.sh`.

Проверка установки:

```bash
sudo -iu hdfs hadoop version
```

Ожидается `Hadoop 3.4.3`.

Имена `team-23-en`, `team-23-nn`, `team-23-00`, `team-23-01` в `/etc/hosts` должны указывать на `10.23.0.10`–`10.23.0.13`. Этих имён не должно быть на строке `127.0.1.1`.

## Конфигурация

Одни и те же файлы из `conf/` копируются в `/opt/hadoop/etc/hadoop` на все узлы.

`core-site.xml`:

```xml
<property>
  <name>fs.defaultFS</name>
  <value>hdfs://team-23-nn:9000</value>
</property>
<property>
  <name>hadoop.tmp.dir</name>
  <value>/var/lib/hadoop/tmp</value>
</property>
```

`hdfs-site.xml`:

```xml
<property>
  <name>dfs.replication</name>
  <value>3</value>
</property>
<property>
  <name>dfs.namenode.name.dir</name>
  <value>file:///var/lib/hadoop/namenode</value>
</property>
<property>
  <name>dfs.datanode.data.dir</name>
  <value>file:///var/lib/hadoop/datanode</value>
</property>
<property>
  <name>dfs.namenode.secondary.http-address</name>
  <value>team-23-en:9868</value>
</property>
<property>
  <name>dfs.namenode.checkpoint.dir</name>
  <value>file:///var/lib/hadoop/namesecondary</value>
</property>
<property>
  <name>dfs.namenode.checkpoint.edits.dir</name>
  <value>file:///var/lib/hadoop/namesecondary</value>
</property>
<property>
  <name>dfs.namenode.safemode.min.datanodes</name>
  <value>3</value>
</property>
```

`workers`:

```
team-23-en
team-23-00
team-23-01
```

## SSH

На `team-23-nn` у пользователя `hdfs` создаётся ключ. Публичная часть кладётся в `/home/hdfs/.ssh/authorized_keys` на всех четырёх узлах. С NameNode `hdfs` входит по SSH на `team-23-en`, `team-23-nn`, `team-23-00`, `team-23-01` без пароля.

```bash
sudo -u hdfs -H ssh-keygen -t ed25519 -N "" -f /home/hdfs/.ssh/id_ed25519
```

## Форматирование

Один раз на NameNode:

```bash
sudo -u hdfs -H /opt/hadoop/bin/hdfs namenode -format -nonInteractive
```

Перед запуском:

```bash
sudo -u hdfs -H hdfs getconf -namenodes
sudo -u hdfs -H hdfs getconf -secondarynamenodes
```

Ожидается `team-23-nn` и `team-23-en`.

## Запуск и проверка

На NameNode:

```bash
sudo -u hdfs -H /opt/hadoop/sbin/start-dfs.sh
sudo -iu hdfs jps
sudo -u hdfs -H /opt/hadoop/sbin/stop-dfs.sh
```

| Узел | Процессы `jps` |
|---|---|
| `team-23-nn` | `NameNode` |
| `team-23-en` | `SecondaryNameNode`, `DataNode` |
| `team-23-00`, `team-23-01` | `DataNode` |

Веб-интерфейсы:

- NameNode: <http://team-23-nn:9870/>
- DataNode: <http://team-23-en:9864/>, <http://team-23-00:9864/>, <http://team-23-01:9864/>
- Secondary NameNode: <http://team-23-en:9868/>

В интерфейсе NameNode — 3 живых DataNode, без dead.

```bash
sudo -u hdfs -H hdfs dfsadmin -report
sudo -u hdfs -H hdfs dfsadmin -safemode get
sudo -u hdfs -H hdfs dfs -mkdir -p /user/hdfs
echo check | sudo -u hdfs -H hdfs dfs -put -f - /user/hdfs/cluster-check.txt
sudo -u hdfs -H hdfs fsck /user/hdfs/cluster-check.txt -files -blocks
```

Ожидается `Safe mode is OFF`, `Live datanodes (3)`, `HEALTHY`, `replication=3`. В `/var/log/hadoop` нет строк `ERROR` и `FATAL`. Строка `RECEIVED SIGNAL 15: SIGTERM` остаётся после `stop-dfs.sh` и ошибкой не является.

`./scripts/verify.sh` выполняет эти проверки. Его запускают после `start.sh`: остановленный кластер он не поднимает.

## Порты

| Порт | Назначение |
|---|---|
| 9000 | RPC NameNode |
| 9870 | веб-интерфейс NameNode |
| 9868 | веб-интерфейс Secondary NameNode |
| 9864 | веб-интерфейс DataNode |
| 9866 | данные DataNode |
| 9867 | IPC DataNode |

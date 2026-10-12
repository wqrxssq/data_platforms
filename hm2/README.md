# YARN

Продолжение [ДЗ 1](../hm1/README.md): YARN и веб-интерфейсы через localhost, как уточнили в чате

На стенде уже работают HDFS, Hadoop 3.4.3 и Java 17

| Узел | Новые службы |
|---|---|
| team-23-nn | ResourceManager |
| team-23-en | NodeManager, JobHistory, nginx |
| team-23-00, team-23-01 | NodeManager |

## Запуск

Команды выполняются на edge (`team-23-en`) от `team`, нужны sudo без пароля и SSH-ключ `~/.ssh/team_internal` для остальных узлов

Hadoop установлен в `/opt/hadoop`, службы запускаются от `hdfs`

Из каталога репозитория:

```bash
cd hm2
sudo -u hdfs -H /opt/hadoop/bin/hdfs dfsadmin -report
sudo -u hdfs -H /opt/hadoop/bin/hdfs dfsadmin -safemode get
```

Перед запуском должны быть `Live datanodes (3)` и `Safe mode is OFF`

```bash
./scripts/setup.sh    # настройки и каталоги
./scripts/start.sh    # запуск YARN и JobHistory
./scripts/check.sh    # проверка через WordCount
./scripts/publish.sh  # nginx для веб-интерфейсов
```

Старые настройки сохраняются в `/var/backups/hadoop-hm2-ДАТА-ВРЕМЯ` на каждом узле

На NodeManager выделены 1536 МБ и 1 vcore, контейнерам WordCount — по 512 МБ

## Веб-интерфейсы

На ноутбуке из папки `hm2` локальной копии репозитория:

```bash
./scripts/open-ui.sh -i ~/.ssh/mts_course_ed25519 -o IdentitiesOnly=yes
```

Указать свой ключ от стенда, оставить терминал открытым и перейти на [localhost:18080](http://localhost:18080/) — там ссылки на все интерфейсы

nginx слушает localhost на edge, SSH пробрасывает порты на ноутбук

| Интерфейс | Порт на localhost |
|---|---|
| ResourceManager | 18088 |
| JobHistory | 18089 |
| NameNode | 18070 |
| SecondaryNameNode | 18068 |
| NodeManager на team-23-en / team-23-00 / team-23-01 | 18042 / 18043 / 18044 |
| DataNode на team-23-en / team-23-00 / team-23-01 | 18064 / 18065 / 18066 |

`Ctrl+C` закрывает подключение, службы продолжают работать

Если соединение оборвалось по таймауту, запустить `open-ui.sh` ещё раз

## Проверка

`check.sh` проверяет три NodeManager, запускает WordCount и проверяет JobHistory и HDFS

Ожидаемый результат — `hadoop 2`, `yarn 1`, в конце — `Проверка пройдена`

Логи сохраняются в `evidence/`, данные — в `/user/hdfs/hm2-...` в HDFS

Проверено на team-23 12 октября в 17:05 МСК: три NodeManager в RUNNING, задача `application_1791813134842_0002` завершилась с SUCCEEDED, HDFS — HEALTHY

Все 10 веб-интерфейсов и переходы в историю задачи и логи открылись через localhost

## Остановка

На edge из `hm2`:

```bash
./scripts/stop.sh
```

Останавливаются YARN и JobHistory, HDFS остаётся работать

Повторный запуск — `./scripts/start.sh`, после перезагрузки ВМ службы также нужно запустить заново

Логи служб: `/var/log/hadoop` и `/var/log/nginx/hm2-error.log`

# mongo-sharding

Команды запускайте из этого каталога. Повторный прогон: `make down`.

## 1. Инициализация

`make init` поднимает сервисы, создает replica set для `configSrv`, `shard1` и `shard2`, включает шардирование `somedb.helloDoc` с ключом `{ _id: "hashed" }` и вставляет 1000 документов.

```shell
make init
```

## 2. Проверка

http://localhost:8080: `documents_count` не меньше 1000, в `shards` два шарда.

```shell
make count
```

Оба значения больше нуля, их сумма совпадает с общим числом в приложении.

# sharding-repl-cache

Команды запускайте из этого каталога. Перед этим остановите `mongo-sharding-repl`: оба проекта занимают порт 8080. Повторный прогон: `make down`.

## 1. Инициализация

`make init` поднимает сервисы, создает replica set из трех узлов для `configSrv`, `shard1` и `shard2`, включает шардирование `somedb.helloDoc` с ключом `{ _id: "hashed" }` и вставляет 1000 документов. Ответы `GET /helloDoc/users` кешируются в Redis.

```shell
make init
```

## 2. Проверка

http://localhost:8080: `documents_count` не меньше 1000, в `shards` два шарда и у каждого три хоста, `cache_enabled` равен `true`.

```shell
make count
```

Оба значения больше нуля, их сумма совпадает с общим числом в приложении.

```shell
make cache
```

Первый вызов `/helloDoc/users` идет в MongoDB и длится около секунды. Второй быстрее 100 мс.

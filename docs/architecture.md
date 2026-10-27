# Мобильный мир

**Автор:** Артур Валиуллин  
**Дата:** 27.10.2026

На распродаже один API и одна нода MongoDB не успевали оформлять заказы: очередь упиралась в тайм-аут. Данные лежат на кластере из `schemas/architecture.drawio`. `pymongo-api` передает запросы в `mongos`, документы лежат на `shard1` и `shard2`. Каждый шард является replica set. Каталог кэшируется в Redis.

База называется `mobileworld`. Запись идет с `writeConcern: "majority"`. Статус заказа читается с primary. Промах кэша каталога читается с `secondaryPreferred`.

| Коллекция | Как `mongos` выбирает шард |
| :- | :- |
| orders | хеш `user_id`, затем `created_at` |
| products | хеш `_id` |
| carts | хеш `owner_key` |

- [Схемы коллекций для шардирования](collections.md)
- [Горячие шарды](hot-shards.md)
- [Чтение с реплик](reads.md)
- [Переход на Cassandra](cassandra.md)

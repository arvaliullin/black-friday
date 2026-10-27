# Горячие шарды

70% запросов к категории `electronics` перегрузили один шард: товары этой категории лежали на нем вместе. Ключ `{ category: 1 }` или `{ category: 1, price: 1 }` собирает популярную категорию в один диапазон. Балансировщик не раскладывает одно значение ключа по разным шардам. Чанк, который из-за этого нельзя поделить, становится jumbo.

Для `products` выбран ключ `{ _id: "hashed" }`. Товары одной категории получают разные хеши и расходятся по `shard1` и `shard2`. Запрос каталога после этого идет на все шарды, повторные ответы отдает Redis.

Один популярный товар при этом ключе остается одним документом. `moveChunk` и `reshardCollection` его не делят. Ровные чанки и рост `writeConflicts` на одном `_id` означают горячий документ, а не перекос раскладки.

Порог: один шард держит заметно больше чанков `products` или около 70% его операций дольше нескольких минут.

| Метрика | Где смотреть | Что считать перекосом |
| :- | :- | :- |
| Число чанков | `config.chunks` | Большая доля чанков `products` на одном шарде |
| `opcounters`, `opLatencies` | `serverStatus` на primary каждого шарда | Один шард выполняет около 70% операций `products` |
| `currentQueue` | `serverStatus.globalLock` | Очередь копится только на одном primary |
| Jumbo и балансировщик | `sh.status()` | Чанк категории нельзя перенести, балансировщик выключен или миграция зависла |
| Лаг реплики | `replSetGetStatus` | Secondary горячего шарда отстает |

Число чанков считается через `mongos`:

```javascript
const products = db.getSiblingDB("config").collections.findOne({ _id: "mobileworld.products" })
db.getSiblingDB("config").chunks.aggregate([
  { $match: { uuid: products.uuid } },
  { $group: { _id: "$shard", chunks: { $sum: 1 } } }
])
```

Операции и очередь смотрят на primary шарда, не на `mongos`:

```javascript
db.serverStatus().opcounters
db.serverStatus().opLatencies
db.serverStatus().globalLock.currentQueue
```

Балансировщик включен. Окно миграций стоит на ночь, чтобы перенос чанков не шел в пик распродажи. `moveChunk` переносит чанк сразу и окна не ждет. Новый шард через `sh.addShard` сам jumbo-чанк не разрезает. Зоны, которые привязывают всю категорию `electronics` к одному шарду, не используются: они закрепляют перекос.

```javascript
sh.startBalancer()
db.getSiblingDB("config").settings.updateOne(
  { _id: "balancer" },
  { $set: { activeWindow: { start: "01:00", stop: "05:00" } } },
  { upsert: true }
)
sh.moveChunk("mobileworld.products", { _id: "phone-x" }, "shard2")
```

Если диапазон категории поделить нельзя, коллекцию перекладывают на ключ `{ _id: "hashed" }`:

```javascript
sh.reshardCollection("mobileworld.products", { _id: "hashed" })
```

# Мобильный мир

**Автор:** Артур Валиуллин  
**Дата:** 27.10.2026

## Схемы коллекций для шардирования

На распродаже один API и одна нода MongoDB не успевали оформлять заказы: очередь упиралась в тайм-аут. Данные лежат на кластере из `schemas/architecture.drawio`. `pymongo-api` передает запросы в `mongos`, документы лежат на `shard1` и `shard2`. Каждый шард является replica set. Каталог кэшируется в Redis. База называется `mobileworld`. Запись идет с `writeConcern: "majority"`. Статус заказа читается с primary. Промах кэша каталога читается с `secondaryPreferred`.

| Коллекция | Как `mongos` выбирает шард |
| :- | :- |
| orders | хеш `user_id` |
| products | хеш `_id` |
| carts | хеш `owner_key` |

Идентификаторы выдает приложение в виде UUID. Деньги хранятся как `Decimal128`, время как `ISODate` UTC. Геозона и категория хранятся кодами.

### orders

В заказе снимок позиций: цена и название на момент покупки.

| Поле | Тип | Роль |
| :- | :- | :- |
| `_id` | string | Идентификатор заказа и ключ идемпотентности |
| `user_id` | string | Покупатель. Шард-ключ |
| `created_at` | ISODate | Время оформления. Шард-ключ |
| `status` | string | `reserving`, `created`, `rejected` |
| `geo_zone` | string | `moscow`, `ekaterinburg`, `kaliningrad` |
| `items` | array | `product_id`, `name`, `category`, `price` Decimal128, `quantity` int |
| `reserved` | array of string | Позиции, по которым остаток уже списан |
| `total` | Decimal128 | Сумма |
| `updated_at` | ISODate | Последнее изменение |

```javascript
{
  _id: "order-1",
  user_id: "user-1",
  created_at: ISODate("2026-11-27T18:04:11Z"),
  status: "created",
  geo_zone: "moscow",
  items: [
    { product_id: "phone-x", name: "Смартфон X", category: "electronics", price: Decimal128.fromString("49990.00"), quantity: 1 },
    { product_id: "book-1", name: "История города", category: "books", price: Decimal128.fromString("890.00"), quantity: 1 }
  ],
  reserved: ["phone-x", "book-1"],
  total: Decimal128.fromString("50880.00"),
  updated_at: ISODate("2026-11-27T18:04:11Z")
}
```

### products

Остаток каждой зоны хранится элементом массива `stock`. `$elemMatch` проверяет количество нужной зоны и уменьшает только её.

| Поле | Тип | Роль |
| :- | :- | :- |
| `_id` | string | Идентификатор товара. Шард-ключ |
| `name` | string | Наименование |
| `category` | string | `electronics`, `books`, `audio`, `appliances` |
| `price` | Decimal128 | Текущая цена |
| `stock` | array | `{ geo_zone: string, qty: int }` |
| `attributes` | object | Дополнительные свойства: `color`, `size` и другие |
| `updated_at` | ISODate | Последнее изменение |

```javascript
{
  _id: "phone-x",
  name: "Смартфон X",
  category: "electronics",
  price: Decimal128.fromString("49990.00"),
  stock: [
    { geo_zone: "moscow", qty: 40 },
    { geo_zone: "ekaterinburg", qty: 50 },
    { geo_zone: "kaliningrad", qty: 30 }
  ],
  attributes: { color: "black", size: "128GB" },
  updated_at: ISODate("2026-11-27T18:04:11Z")
}
```

### carts

`owner_key` равен `user_id` или `session_id`. Оба фильтра активной корзины читают один шард. У гостя `user_id: null`, шард-ключ при этом заполнен.

| Поле | Тип | Роль |
| :- | :- | :- |
| `_id` | string | Идентификатор корзины |
| `owner_key` | string | Шард-ключ |
| `user_id` | string или null | Покупатель |
| `session_id` | string или null | Сессия гостя |
| `items` | array | `{ product_id: string, quantity: int }` |
| `status` | string | `active`, `ordered`, `abandoned` |
| `merged_sessions` | array of string | Сессии, уже влитые в корзину |
| `created_at`, `updated_at`, `expires_at` | ISODate | Создание, изменение, момент TTL |

```javascript
{
  _id: "cart-1",
  owner_key: "user-1",
  user_id: "user-1",
  session_id: null,
  items: [{ product_id: "phone-x", quantity: 1 }],
  status: "active",
  merged_sessions: [],
  created_at: ISODate("2026-11-27T17:40:00Z"),
  updated_at: ISODate("2026-11-27T17:58:12Z"),
  expires_at: ISODate("2026-12-11T17:40:00Z")
}
```

### Шард-ключи

Стратегия всех трех коллекций: hashed. Обращения точечные. Монотонное время и поле с малой кардинальностью собирают пик распродажи на одном шарде.

| Кандидат | Коллекция | Кардинальность | Один шард | Итог |
| :- | :- | :- | :- | :- |
| `{ created_at: 1 }` | orders | Высокая, растёт со временем | Заказы за интервал | Весь пик в последнем чанке |
| `{ _id: "hashed" }` | orders | Высокая | Статус по `_id` | История покупателя идет как scatter-gather |
| `{ geo_zone: 1 }` | orders | Низкая | Заказы одной зоны | Москва занимает шард |
| `{ user_id: "hashed", created_at: 1 }` | orders | Высокая | Вставка, история, статус | Выбран |
| `{ category: 1, price: 1 }` | products | Мало категорий, объём неравный | Каталог категории | Списание по `product_id` идет как scatter-gather |
| `{ _id: "hashed" }` | products | Высокая | Карточка и списание | Выбран. Каталог идет как scatter-gather |
| `{ user_id: 1 }` | carts | У гостя пусто | Корзина покупателя | Все `null` в одном чанке |
| `{ session_id: 1 }` | carts | Высокая у гостей | Гостевая корзина | Корзина покупателя идет как scatter-gather |
| `{ status: 1 }` | carts | 3 значения | Один статус | Одно значение на шард |
| `{ owner_key: "hashed" }` | carts | Высокая | Обе активные корзины | Выбран |

| Коллекция | Ключ | Выигрыш | Риск |
| :- | :- | :- | :- |
| orders | `{ user_id: "hashed", created_at: 1 }` | Заказы разных покупателей расходятся. История `{ user_id }` попадает на один шард. `created_at` вторым полем режет очень длинную историю | Статус читается как `{ user_id, _id }`. Уникальность `_id` действует внутри шарда. Повтор с тем же `created_at` попадает в тот же чанк |
| products | `{ _id: "hashed" }` | Списание и карточка точечные. В корзине нет категории, поэтому она не может быть префиксом ключа | Каталог `{ category, price }` идёт на все шарды по индексу и закрывается Redis. Горячий SKU остаётся одним документом |
| carts | `{ owner_key: "hashed" }` | Чтение, правка и создание активной корзины точечные. Ключ при смене статуса не меняется | Уникальный индекс одной active-корзины на hashed-ключе недоступен: гонку закрывает повторное чтение. Слияние при логине трогает два шарда. `merged_sessions` не дает влить сессию дважды |

Индексы поверх ключей: история `{ user_id: 1, created_at: -1 }`, каталог `{ category: 1, price: 1 }`, активная корзина `{ owner_key: 1, status: 1 }`, TTL `{ expires_at: 1 }` с `expireAfterSeconds: 0`. TTL-удаление выполняет шард, на котором лежит документ.

### Оформление заказа

Списание и вставка выполняются отдельными точечными командами. Общая транзакция держала бы блокировку горячего товара, пока заказ пишется на другом шарде, и снова удлиняла бы задачу в очереди.

Задача несёт `order_id`, `user_id` и `created_at`.

1. Прочитать заказ. `created` и `rejected` остаток больше не меняют.
2. Если документа нет, вставить его в статусе `reserving` со снимком `items` и пустым `reserved`.
3. Для позиций вне `reserved` выполнить условный `$inc`. Успех дописывает `product_id` в `reserved`.
4. При `modifiedCount == 0` выполняется обратный `$inc` по уже списанным позициям, статус становится `rejected`.
5. Когда списаны все позиции, статус становится `created`, корзина переводится в `ordered`.

### Команды

```javascript
sh.enableSharding("mobileworld")
sh.shardCollection("mobileworld.orders", { user_id: "hashed", created_at: 1 })
sh.shardCollection("mobileworld.products", { _id: "hashed" })
sh.shardCollection("mobileworld.carts", { owner_key: "hashed" })

use mobileworld
db.orders.createIndex({ user_id: 1, created_at: -1 })
db.products.createIndex({ category: 1, price: 1 })
db.carts.createIndex({ owner_key: 1, status: 1 })
db.carts.createIndex({ expires_at: 1 }, { expireAfterSeconds: 0 })
```

```javascript
db.orders.find({ user_id: "user-1" }).sort({ created_at: -1 })
db.orders.findOne({ user_id: "user-1", _id: "order-1" })

db.products.updateOne(
  { _id: "phone-x", stock: { $elemMatch: { geo_zone: "moscow", qty: { $gte: 1 } } } },
  { $inc: { "stock.$.qty": -1 }, $set: { updated_at: new Date() } }
)
db.products.find({ category: "electronics", price: { $gte: Decimal128.fromString("1000"), $lte: Decimal128.fromString("50000") } })

db.carts.updateOne(
  { owner_key: "session-1", status: "active" },
  { $setOnInsert: { owner_key: "session-1", session_id: "session-1", user_id: null, items: [], status: "active", merged_sessions: [], created_at: new Date(), expires_at: new Date(Date.now() + 14 * 864e5) }, $set: { updated_at: new Date() } },
  { upsert: true }
)
db.carts.findOne({ owner_key: "session-1", status: "active" })
db.carts.updateOne(
  { owner_key: "session-1", status: "active" },
  { $pull: { items: { product_id: "phone-x" } }, $set: { updated_at: new Date() } }
)
db.carts.updateOne(
  { owner_key: "user-1", status: "active", merged_sessions: { $ne: "session-1" } },
  { $set: { items: [{ product_id: "phone-x", quantity: 2 }], updated_at: new Date() }, $addToSet: { merged_sessions: "session-1" } }
)
db.carts.updateOne(
  { owner_key: "session-1", status: "active" },
  { $set: { status: "abandoned", updated_at: new Date() } }
)
db.carts.updateOne(
  { owner_key: "user-1", status: "active" },
  { $set: { status: "ordered", updated_at: new Date() } }
)
```

Точечные запросы в `explain("executionStats")` дают `SINGLE_SHARD`. Каталог даёт `SHARD_MERGE`. Замена количества в корзине пересобирает `items` одним pipeline-update: старая позиция товара убирается, новая записывается с нужным количеством. Если корзины покупателя ещё нет, перед слиянием она создаётся с `owner_key`, равным `user_id`.

### Мониторинг

| Симптом | Где смотреть | Действие |
| :- | :- | :- |
| Задача заказа подходит к тайм-ауту, очередь растёт | Метрики очереди, `explain` | Списание и вставка должны быть `SINGLE_SHARD`. Если так и есть, смотреть конфликты записи товара |
| `writeConflicts` растёт на одном `_id` при ровных чанках | `serverStatus.metrics.operation.writeConflicts` на primary `products` | Повторить идемпотентную задачу. Это горячий документ, смена шард-ключа каталога его не размазывает |
| `SHARD_MERGE` на заказе или корзине | `explain` на `mongos` | Вернуть в фильтр `user_id`, `_id` товара или `owner_key`. Для каталога это норма, ответ берётся из Redis; кэш прогревается до распродажи |
| Один шард держит больше чанков, чанк jumbo | `sh.status()` | Окно балансировщика. Jumbo на этих ключах лечится `reshardCollection` |
| Лаг реплики на шарде заказов | `replSetGetStatus` | Статус заказа читать с primary |
| `carts` растёт при живом TTL-индексе | Число документов, лог TTL | Проверить `expires_at` у новых корзин и `expireAfterSeconds: 0` |

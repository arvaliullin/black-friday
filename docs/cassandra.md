# Переход на Cassandra

При 50 000 запросов в секунду добавление шарда в range-based MongoDB перекладывает данные между всеми узлами и роняет latency. Cassandra раскладывает партиции по кольцу токенов. Новый узел забирает только соседние диапазоны.

Заказы переносятся: запись в пик и история по покупателю, ключ `user_id` равномерный. Строка заказа пишется после успешного `$inc` в MongoDB, поэтому недоступный товар не продается. Корзины переносятся вместе с гостевой сессией через `owner_key`: много мелких записей, удалений и TTL. Товары остаются в MongoDB. Остаток списывается условным `$inc`, каталог фильтрует категорию и цену. Ключ по категории собрал бы `electronics` в одну горячую партицию, и новый узел Cassandra ее не разрежет.

У Cassandra нет primary, реплики равноправны. Репликация `NetworkTopologyStrategy`, RF=3. Запросы пика идут с `LOCAL_QUORUM` и не ходят в другой датацентр. История заказов читается с `LOCAL_ONE`.

Горячая партиция возможна у одного очень активного покупателя, не у всей распродажи. Смена числа узлов не меняет ключ и не перекладывает все партиции.

```cql
CREATE KEYSPACE mobileworld WITH replication = {
  'class': 'NetworkTopologyStrategy',
  'dc1': 3
};

CREATE TYPE mobileworld.order_item (
  product_id text,
  name text,
  category text,
  price decimal,
  quantity int
);

CREATE TABLE mobileworld.orders_by_user (
  user_id text,
  created_at timestamp,
  order_id text,
  status text,
  geo_zone text,
  items list<frozen<order_item>>,
  total decimal,
  PRIMARY KEY ((user_id), created_at, order_id)
) WITH CLUSTERING ORDER BY (created_at DESC, order_id ASC)
  AND read_repair = 'BLOCKING';

CREATE TABLE mobileworld.cart_items (
  owner_key text,
  product_id text,
  quantity int,
  status text static,
  user_id text static,
  session_id text static,
  PRIMARY KEY ((owner_key), product_id)
) WITH default_time_to_live = 1209600
  AND read_repair = 'NONE';
```

`created_at` и `geo_zone` не стоят в начале ключа заказа: история и статус покупателя лежат в одной партиции. Позиция корзины это отдельная строка. Статус корзины статический и общий для партиции.

Hinted handoff включен для обеих таблиц и закрывает простой реплики в пределах трех часов (`max_hint_window_in_ms: 10800000`).

У заказов `read_repair = 'BLOCKING'`. Статус читается кворумом, расхождение чинится на этом чтении, и история при `LOCAL_ONE` реже видит старый статус. Задержка появляется только при расхождении реплик.

У корзин `read_repair = 'NONE'`. Клиент читает `LOCAL_QUORUM` и видит свою запись. Блокирующий repair на каждом таком чтении удлинил бы пик.

Anti-entropy repair идет по расписанию для обеих таблиц и успевает до `gc_grace_seconds`. Для корзин он важнее: там удаления и TTL, без repair всплывают старые tombstone.

```shell
nodetool repair -pr mobileworld orders_by_user
nodetool repair -pr mobileworld cart_items
```

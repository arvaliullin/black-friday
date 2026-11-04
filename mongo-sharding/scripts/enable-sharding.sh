#!/bin/bash
set -eu

cd "$(dirname "$0")/.."

until docker compose exec -T mongos mongosh --port 27017 --quiet \
  --eval 'db.runCommand({ ping: 1 }).ok' | grep -q 1
do
  sleep 2
done

docker compose exec -T mongos mongosh --port 27017 --quiet <<EOF
sh.addShard("shard1/shard1:27018")
sh.addShard("shard2/shard2:27018")
sh.shardCollection("somedb.helloDoc", { _id: "hashed" })
use somedb
for (var i = 0; i < 1000; i++) db.helloDoc.insertOne({age: i, name: "ly" + i})
EOF

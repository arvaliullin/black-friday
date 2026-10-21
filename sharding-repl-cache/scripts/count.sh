#!/bin/bash
set -eu

cd "$(dirname "$0")/.."

count_shard() {
  local service="$1"
  docker compose exec -T "$service" mongosh --port 27018 --quiet <<EOF
db.getMongo().setReadPref("secondaryPreferred")
use somedb
db.helloDoc.countDocuments()
EOF
}

count_shard shard1-1
count_shard shard2-1

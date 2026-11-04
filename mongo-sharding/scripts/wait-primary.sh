#!/bin/bash
set -eu

cd "$(dirname "$0")/.."

wait_primary() {
  local service="$1"
  local port="$2"
  until docker compose exec -T "$service" mongosh --port "$port" --quiet \
    --eval 'rs.status().myState' | grep -q '^1$'
  do
    sleep 2
  done
}

wait_primary configSrv 27019
wait_primary shard1 27018
wait_primary shard2 27018

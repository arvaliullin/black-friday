#!/bin/bash
set -eu

cd "$(dirname "$0")/.."

wait_primary() {
  local service="$1"
  local port="$2"
  until docker compose exec -T "$service" mongosh --port "$port" --quiet \
    --eval 'rs.status().members.filter(m => m.stateStr == "PRIMARY").length' | grep -q '^1$'
  do
    sleep 2
  done
}

wait_primary configSrv-1 27019
wait_primary shard1-1 27018
wait_primary shard2-1 27018

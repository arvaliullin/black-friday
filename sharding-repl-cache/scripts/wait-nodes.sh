#!/bin/bash
set -eu

cd "$(dirname "$0")/.."

wait_ping() {
  local service="$1"
  local port="$2"
  until docker compose exec -T "$service" mongosh --port "$port" --quiet \
    --eval 'db.runCommand({ ping: 1 }).ok' | grep -q 1
  do
    sleep 2
  done
}

wait_ping configSrv-1 27019
wait_ping configSrv-2 27019
wait_ping configSrv-3 27019
wait_ping shard1-1 27018
wait_ping shard1-2 27018
wait_ping shard1-3 27018
wait_ping shard2-1 27018
wait_ping shard2-2 27018
wait_ping shard2-3 27018

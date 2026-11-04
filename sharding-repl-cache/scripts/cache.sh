#!/bin/bash
set -eu

url=http://localhost:8080/helloDoc/users

curl -s -o /dev/null -w 'first %{time_total}\n' "$url"
curl -s -o /dev/null -w 'second %{time_total}\n' "$url"

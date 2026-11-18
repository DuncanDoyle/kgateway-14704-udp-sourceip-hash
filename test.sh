#!/usr/bin/env bash
# Sends one datagram from each of N different source ports (= N new udp_proxy sessions) from ONE
# client IP, and counts which backend answered.
#   Expected (sourceIP hash works): all N replies from the same backend.
#   Bug:                            replies spread over backend-a/b/c.
set -euo pipefail
cd "$(dirname "$0")"

N=${N:-30}
VERSIONS=${VERSIONS:-"v1.39.6 v1.40.2"}
CONFIGS=${CONFIGS:-"envoy-kgateway-pr.yaml envoy-control.yaml"}

for v in $VERSIONS; do
  for c in $CONFIGS; do
    export ENVOY_VERSION=$v ENVOY_CONFIG=$c
    docker compose up -d --quiet-pull >/dev/null 2>&1
    # Wait until Envoy has resolved all 3 endpoints.
    for _ in $(seq 1 30); do
      healthy=$(docker compose exec -T client sh -c \
        "echo | socat -T1 - TCP4:envoy:9901 >/dev/null 2>&1; echo ok" 2>/dev/null || true)
      [ -n "$healthy" ] && break
      sleep 1
    done
    sleep 3
    replies=""
    for i in $(seq 1 "$N"); do
      port=$((40000 + i))
      r=$(docker compose exec -T client sh -c \
        "echo ping | socat -T1 - UDP4:envoy:10000,sourceport=$port 2>/dev/null" | tr -d '\r' || true)
      replies+="${r:-no-reply}"$'\n'
    done
    echo "== Envoy $v, $c (client IP $(docker compose exec -T client hostname -i | tr -d '\r'), $N sessions)"
    printf "%s" "$replies" | sort | uniq -c
    docker compose down -t 1 >/dev/null 2>&1
  done
done

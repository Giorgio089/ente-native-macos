#!/bin/bash
# launchd-Wrapper für museum: wartet auf Postgres + MinIO, startet dann museum.
# Wird vom launchd-Agent home.ente.museum aufgerufen (ProgramArguments).
#
# Anpassen: Pfad, Ports, falls abweichend von den Defaults in dieser Anleitung.

set -u

MUSEUM_DIR="/PATH/TO/ente/museum/server"   # <-- anpassen
PG_PORT=5433
MINIO_PORT=3200

export PATH="/opt/homebrew/bin:/usr/bin:/bin:$PATH"
cd "$MUSEUM_DIR" || exit 1

wait_for() {
  local host=$1 port=$2 name=$3 tries=0
  until nc -z "$host" "$port" 2>/dev/null; do
    tries=$((tries + 1))
    if [ $tries -ge 60 ]; then
      echo "[run-museum] $name ($host:$port) nach 60s nicht erreichbar — starte museum trotzdem" >&2
      break
    fi
    echo "[run-museum] warte auf $name ($host:$port)..." >&2
    sleep 1
  done
}

wait_for 127.0.0.1 "$PG_PORT" postgres
wait_for 127.0.0.1 "$MINIO_PORT" minio
echo "[run-museum] Abhängigkeiten bereit, starte museum" >&2
exec ./museum

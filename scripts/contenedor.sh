#!/usr/bin/env bash
set -euo pipefail

docker rm -f estado-c 2>/dev/null || true

docker run -d \
  --name estado-c \
  --restart unless-stopped \
  --user 65534:65534 \
  --read-only \
  --tmpfs /tmp:rw,noexec,nosuid,size=16m \
  --cap-drop=ALL \
  --security-opt=no-new-privileges \
  --memory=128m \
  --memory-swap=128m \
  --pids-limit=32 \
  -p 127.0.0.1:8081:8082 \
  -v /opt/estado/estado.py:/app/estado.py:ro \
  python:3.12-alpine \
  python3 /app/estado.py

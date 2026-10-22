#!/usr/bin/env bash
# Run this once on the machine that hosts the container:
#   ./setup.sh
#   docker compose up -d --build
set -euo pipefail
cd "$(dirname "$0")"

if [ ! -f .env ]; then
  cp .env.example .env
  # 8 characters: the RFB (VNC) password limit.
  PASS="$(LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 8)"
  sed -i "s/^VNC_PASSWORD=.*/VNC_PASSWORD=${PASS}/" .env
  echo "Created .env with a random VNC password: ${PASS}"
  echo "It is also stored in .env (not committed)."
else
  PASS="$(grep -E '^VNC_PASSWORD=' .env | cut -d= -f2- || true)"
  echo ".env already exists; keeping it."
  [ -n "$PASS" ] && echo "VNC password: ${PASS}"
fi

mkdir -p shared

echo
echo "Next: docker compose up -d --build"
echo "Then open: http://127.0.0.1:6080/vnc.html  (password above)"

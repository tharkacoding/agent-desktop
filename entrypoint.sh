#!/usr/bin/env bash
# Starts the desktop container: prepares the VNC password, logs Codex in with the API key when given,
# bootstraps/updates AgentOS, then hands over to supervisord (Xvfb, XFCE, x11vnc, noVNC, AgentOS).
set -euo pipefail

export HOME=/home/agent
export DISPLAY=:0
AGENT=agent
PLATFORM=/home/agent/agent-platform
VENV=/home/agent/venv

log() { printf '[entrypoint] %s\n' "$*"; }

# --- 1. VNC password -------------------------------------------------------------------------
# x11vnc only uses the first 8 characters (RFB limit), so trim instead of failing.
if [ -z "${VNC_PASSWORD:-}" ]; then
  echo "[entrypoint] VNC_PASSWORD is not set. Run ./setup.sh on the host (it writes .env), then start again." >&2
  exit 1
fi
VNC_PASS="$(printf '%s' "$VNC_PASSWORD" | cut -c1-8)"
install -d -o "$AGENT" -g "$AGENT" -m 700 /home/agent/.vnc
runuser -u "$AGENT" -- /usr/bin/x11vnc -storepasswd "$VNC_PASS" /home/agent/.vnc/passwd >/dev/null 2>&1
log "VNC password set (${#VNC_PASS} characters)."

# --- 2. directories owned by the desktop user ------------------------------------------------
for d in "$PLATFORM" /data /home/agent/shared /home/agent/.chrome-profile \
         /home/agent/.codex /home/agent/.local/share/opencode /home/agent/.run; do
  mkdir -p "$d"
  chown "$AGENT:$AGENT" "$d"
done
chmod 700 /home/agent/.run

# XFCE and Chrome want a session bus and a runtime dir.
export XDG_RUNTIME_DIR=/home/agent/.run

# --- 3. Codex CLI: log in with the key for this run only (never written to disk by us) --------
if [ -n "${OPENAI_API_KEY:-}" ] && command -v codex >/dev/null 2>&1; then
  if runuser -u "$AGENT" -- env OPENAI_API_KEY="$OPENAI_API_KEY" HOME=/home/agent \
       bash -lc 'printf "%s" "$OPENAI_API_KEY" | codex login --with-api-key' >/dev/null 2>&1; then
    log "Codex CLI logged in with OPENAI_API_KEY."
  else
    log "codex login --with-api-key failed (ignored); run login-codex inside the desktop."
  fi
fi

# --- 4. AgentOS: clone once, pull on every start, install deps, build the web UI --------------
runuser -u "$AGENT" -- env HOME=/home/agent GIT_TERMINAL_PROMPT=0 bash -lc '
  set -u
  cd /home/agent/agent-platform
  if [ -z "$(ls -A . 2>/dev/null)" ]; then
    echo "[entrypoint] cloning agent-platform"
    git clone https://github.com/tharkacoding/agent-platform.git .
  else
    git pull --ff-only || echo "[entrypoint] git pull skipped (offline or diverged) - continuing"
  fi
'

runuser -u "$AGENT" -- env HOME=/home/agent bash -lc '
  set -u
  cd /home/agent/agent-platform || exit 0
  if [ -f requirements-gateway.txt ]; then
    want="$(sha256sum requirements-gateway.txt | cut -d" " -f1)"
    have="$(cat /home/agent/.agentos-req.sha 2>/dev/null || true)"
    if [ "$want" != "$have" ]; then
      echo "[entrypoint] installing gateway requirements"
      /home/agent/venv/bin/pip install --upgrade pip >/dev/null
      /home/agent/venv/bin/pip install -r requirements-gateway.txt || echo "[entrypoint] pip install failed - continuing"
      printf "%s" "$want" > /home/agent/.agentos-req.sha
    fi
  fi
  if [ ! -d web/dist ] && [ -f web/package.json ]; then
    echo "[entrypoint] building AgentOS web UI"
    ( cd web && npm install && npm run build ) || echo "[entrypoint] web build failed - continuing"
  fi
'

# --- 5. everything supervised -----------------------------------------------------------------
log "starting supervisord (noVNC :6080, AgentOS :7860)"
exec /usr/bin/supervisord -n -c /etc/supervisor/conf.d/supervisord.conf

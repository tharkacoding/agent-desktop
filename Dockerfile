# agent-desktop: a full Linux desktop in Docker with Chrome, Codex CLI, OpenCode and AgentOS.
#
# One container, one user ("agent", uid 1000), everything supervised.
# Built for Ubuntu 24.04 (glibc, Chrome, Node 20, Python 3).

FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    HOME=/home/agent \
    DISPLAY=:0

ARG AGENT_UID=1000
ARG AGENT_GID=1000

# --- base tools, desktop, VNC, noVNC, Python -------------------------------------------------
RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl wget git gnupg unzip xz-utils procps \
      xvfb x11vnc novnc websockify supervisor \
      dbus dbus-x11 xfce4 xfce4-terminal mousepad xdotool scrot \
      python3 python3-venv python3-pip \
      fonts-liberation fonts-dejavu-core \
    && rm -rf /var/lib/apt/lists/*

# --- Google Chrome from the official .deb (never snap) ---------------------------------------
RUN curl -fsSL -o /tmp/google-chrome.deb \
      https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb \
    && apt-get update \
    && apt-get install -y /tmp/google-chrome.deb \
    && rm -f /tmp/google-chrome.deb \
    && rm -rf /var/lib/apt/lists/*

# --- Node.js 20 (NodeSource) + the two CLIs --------------------------------------------------
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get install -y nodejs \
    && npm install -g @openai/codex opencode-ai@latest \
    && npm cache clean --force \
    && rm -rf /var/lib/apt/lists/*

# --- user "agent" (uid 1000), home dirs, Python venv -----------------------------------------
RUN groupadd -g "${AGENT_GID}" agent \
    && useradd -m -u "${AGENT_UID}" -g agent -s /bin/bash agent \
    && mkdir -p /home/agent/Desktop \
                /home/agent/.vnc \
                /home/agent/.chrome-profile \
                /home/agent/.codex \
                /home/agent/.local/share/opencode \
                /home/agent/agent-platform \
                /home/agent/shared \
                /data \
    && chown -R agent:agent /home/agent /data

RUN python3 -m venv /home/agent/venv \
    && /home/agent/venv/bin/pip install --upgrade pip \
    && chown -R agent:agent /home/agent/venv

# --- short commands, desktop icons, supervisor, entrypoint -----------------------------------
COPY scripts/ /usr/local/bin/
RUN chmod +x /usr/local/bin/chrome \
             /usr/local/bin/xdg-open \
             /usr/local/bin/agentos-ui \
             /usr/local/bin/login-codex \
             /usr/local/bin/login-codex-code \
             /usr/local/bin/login-opencode \
             /usr/local/bin/work

COPY desktop/ /home/agent/Desktop/
RUN chmod +x /home/agent/Desktop/*.desktop \
    && chown -R agent:agent /home/agent/Desktop

COPY supervisord.conf /etc/supervisor/conf.d/supervisord.conf
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

EXPOSE 6080 5900 7860
USER root
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]

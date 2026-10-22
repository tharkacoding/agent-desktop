# agent-desktop

A complete Linux desktop in Docker: **XFCE over noVNC**, **Google Chrome**, **Codex CLI**, **OpenCode**, and your
**AgentOS** gateway (https://github.com/tharkacoding/agent-platform) — all in one container, all supervised,
all reachable from the browser on your own machine.

One command starts everything:

```bash
docker compose up -d --build
```

Then open **http://127.0.0.1:6080/vnc.html**.

---

## What is inside

| Piece | Details |
|---|---|
| Base | `ubuntu:24.04` |
| User | `agent`, uid/gid 1000, home `/home/agent` |
| Display | Xvfb `:0`, 1280x720x24 |
| Desktop | XFCE4 + `xfce4-terminal`, `mousepad`, `xdotool`, `scrot`, `dbus-x11` |
| Remote view | `x11vnc` on 5900 + `noVNC`/`websockify` on 6080 |
| Browser | Google Chrome from the official `.deb` (not snap) |
| Node | Node.js 20 (NodeSource) |
| CLIs | `@openai/codex`, `opencode-ai@latest` (global npm) |
| Python | Python 3 venv at `/home/agent/venv` for AgentOS |
| AgentOS | cloned to `/home/agent/agent-platform`, gateway on `127.0.0.1:7860` |
| Supervisor | `supervisord` runs Xvfb, XFCE, x11vnc, noVNC, AgentOS with `autorestart=true` |

### Short commands

Inside the desktop (terminal or the "Run" dialog), these are in `/usr/local/bin`:

| Command | What it does |
|---|---|
| `chrome` | Chrome with the persistent profile and `--no-sandbox` |
| `xdg-open <url>` | Opens the URL in the desktop Chrome (also used by CLIs) |
| `agentos-ui` | Opens `http://127.0.0.1:7860` in Chrome |
| `login-codex` | `codex login` (browser-based sign-in) |
| `login-codex-code` | `codex login --device-auth` (type a code on another device) |
| `login-opencode` | `opencode auth login` |
| `work` | Drops you into `/home/agent/agent-platform` |

Desktop icons for Chrome, AgentOS and Terminal are in `/home/agent/Desktop`.

---

## 1. Install Docker (once, on the Linux machine)

Ubuntu / Debian:

```bash
sudo apt update
sudo apt install -y docker.io docker-compose-v2
sudo usermod -aG docker "$USER"   # log out and back in
```

Check:

```bash
docker run --rm hello-world
docker compose version
```

Any Docker Engine + Compose v2 works. Docker Desktop works too.

## 2. Get the repo

```bash
git clone https://github.com/tharkacoding/agent-desktop.git
cd agent-desktop
```

## 3. Configure

```bash
./setup.sh
```

This copies `.env.example` to `.env`, generates a random **8-character VNC password**, and prints it.
Then edit `.env` and add the keys you have:

```dotenv
VNC_PASSWORD=Ab3xY9zQ
OPENAI_API_KEY=sk-...
ANTHROPIC_API_KEY=sk-ant-...
OPENROUTER_API_KEY=sk-or-...
```

Notes:

- `VNC_PASSWORD` is capped at 8 characters (VNC protocol limit); longer values are trimmed.
- Keys are read from `.env` at runtime. They are **not** baked into the image and `.env` is git-ignored.
- If `OPENAI_API_KEY` is set, the entrypoint runs `codex login --with-api-key` on start so Codex is ready.
  Failures there are ignored — you can always run `login-codex` in the desktop.
- OpenCode reads `OPENAI_API_KEY`, `ANTHROPIC_API_KEY`, `OPENROUTER_API_KEY` from the environment;
  use `login-opencode` only for providers that need an interactive login.

## 4. Start

```bash
docker compose up -d --build
```

First build takes a while (desktop packages, Chrome, Node, npm CLIs). Then:

- **Desktop:** http://127.0.0.1:6080/vnc.html — click *Connect*, enter the VNC password.
- **AgentOS:** open `agentos-ui` (or http://127.0.0.1:7860) *inside the desktop*. The gateway binds
  `127.0.0.1` inside the container by design, so the published 7860 mapping cannot reach it from the host.
  If you want host access, change `--host 127.0.0.1` to `--host 0.0.0.0` in `supervisord.conf` and rebuild;
  the compose mapping still exposes it on host loopback only.

Follow the startup log:

```bash
docker compose logs -f desktop
```

Stop / start:

```bash
docker compose stop
docker compose start
docker compose down          # keep volumes
docker compose down -v       # also delete profiles, logins and AgentOS data
```

## 5. Remote access from another machine

Both ports are published on `127.0.0.1` only. To use the desktop from a laptop, forward the port over SSH:

```bash
ssh -L 6080:localhost:6080 user@server
```

Then open http://127.0.0.1:6080/vnc.html locally. Do the same for 7860 if you want AgentOS directly.
Alternatively, change the port mapping in `docker-compose.yml` — but only behind a firewall/VPN, since the
VNC password is the only gate.

---

## AgentOS lifecycle

The entrypoint, running before supervisord, does this on every container start:

1. If `/home/agent/agent-platform` is empty, `git clone https://github.com/tharkacoding/agent-platform.git`.
2. `git pull --ff-only` when it already exists. Offline or diverged: logs a message and continues.
3. If `requirements-gateway.txt` changed (sha256 marker at `/home/agent/.agentos-req.sha`), runs
   `pip install -r requirements-gateway.txt` into `/home/agent/venv`.
4. If `web/dist` is missing, runs `npm install && npm run build` in `web/`.
5. Starts `uvicorn aap.api.app:app --host 127.0.0.1 --port 7860` under supervisord.

AgentOS data (`AAP_DATA_DIR`) is `/data`, which is a named volume. That is where its registry, checkpoints,
skills, memory and workspaces live.

The gateway's default LLM endpoint is `host.docker.internal:20128` — the compose file maps
`host.docker.internal` to the host gateway, so a model server running on the host is reachable. Override with
`AAP_LLM_BASE_URL` / `AAP_LLM_MODEL` in `.env` if yours differs. Note: AgentOS's `runner` and `browser`
sandbox services are separate containers in the upstream compose; here only the gateway runs, so tools that
need those services report them unavailable. Set `AAP_RUNNER_URL` / `AAP_BROWSER_URL` in `.env` if you run
those services somewhere reachable.

## Volumes

| Volume | Container path | Holds |
|---|---|---|
| `chrome-profile` | `/home/agent/.chrome-profile` | Chrome profile: logins, cookies, history |
| `codex-home` | `/home/agent/.codex` | Codex CLI config and auth |
| `opencode-data` | `/home/agent/.local/share/opencode` | OpenCode data and auth |
| `agent-platform` | `/home/agent/agent-platform` | AgentOS checkout (and `web/dist`) |
| `agentos-data` | `/data` | AgentOS runtime data |
| `./shared` (bind) | `/home/agent/shared` | Files you want to move in/out from the host |

`./shared` is created by `setup.sh` and ignored by git.

## Security notes

- The container is **not** privileged, has no Docker socket, no host networking, and publishes ports on
  loopback only.
- `shm_size: 2gb` so Chrome does not crash on heavy pages.
- Chrome runs with `--no-sandbox` because it is already namespaced by the container. Do not run this image
  with `--privileged` or mount `/var/run/docker.sock` into it.
- Keep `.env` private. `docker compose config` prints the values, so avoid pasting its output.

## Troubleshooting

**noVNC says "Failed to connect to server".**
`docker compose logs desktop` — look for x11vnc. Usually the password file or port 5900 is the issue; restart
with `docker compose restart desktop`.

**The desktop is grey / no panel.**
XFCE is still starting, or it crashed. `docker compose logs desktop | grep -i xfce`; the supervisor restarts
it automatically.

**AgentOS shows 502 / connection refused.**
Give the first start a few minutes (clone + pip + web build). Then
`docker compose logs desktop | grep -i agentos` and check http://127.0.0.1:7860 inside the desktop's Chrome.

**`pip install` fails on start.**
It is retried on the next start when `requirements-gateway.txt` changes. To force it:
`docker compose exec desktop /home/agent/venv/bin/pip install -r /home/agent/agent-platform/requirements-gateway.txt`.

**Chrome will not start.**
Run `chrome` in a terminal and read the error; `~/.chrome-profile` may be locked by a crashed process:
`pkill -f chrome` (inside the container) then try again.

**Permission denied on a volume.**
Volumes are owned by `agent` (uid 1000). If you changed `AGENT_UID`, rebuild with the matching
`--build-arg AGENT_UID=...`.

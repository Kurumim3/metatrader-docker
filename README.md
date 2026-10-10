# 📊 MetaTrader Docker

Run **MT4 + MT5** 24/7 on a cheap Linux VPS (1 GB RAM friendly).
Browser access via noVNC, no Windows, no heavy GUI on the host.

> ⚠️ Independent project. **Not affiliated** with MetaQuotes or any broker.
> Automated trading carries real financial risk. Test on a demo account first.

---

## Requirements

| Item | Recommendation |
|---|---|
| OS | Ubuntu Server 22.04 LTS (or Debian) |
| RAM | 1 GB minimum · 2 GB+ recommended |
| Disk | 10 GB free |
| Access | root/sudo |
| Local | SSH client + modern browser |

---

## Quick Start

```bash
git clone https://github.com/Kurumim3/metatrader-docker.git
cd metatrader-docker

# If downloaded from Windows, normalize line endings:
sed -i 's/\r$//' install-mt-docker.sh

sudo bash install-mt-docker.sh
```

After the first run, the shortcut **`sudo mt-menu`** becomes available.

That's it — the script downloads the **official MetaQuotes installers** and runs everything inside a Docker container.

---

## Interactive Menu

| Option | Action |
|---|---|
| **A** | Guided install (base → MT4/MT5 → EAs) |
| **1** | Install base (Docker, swap, image build) |
| **2** | Install / remove MT4 and MT5 |
| **3** | Deploy EAs (.ex4/.ex5), indicators, and sets (.set) |
| **4** | Status and diagnostics |
| **5** | Operations (start / stop / restart) |
| **6** | Maintenance (backup, update, logs, VNC password) |
| **7** | How to access (password + SSH tunnel) |
| **0** | Exit |

Direct commands also work:

```bash
sudo bash install-mt-docker.sh guiada     # full guided install
sudo bash install-mt-docker.sh status     # diagnostics
sudo bash install-mt-docker.sh backup     # backup now
```

---

## Access (noVNC over SSH tunnel)

noVNC is **bound to `127.0.0.1`** — not exposed to the internet.
On **your computer**, open the tunnel:

```bash
ssh -N -p 22 -L 6080:127.0.0.1:6080 root@YOUR_IP
```

Then open in your browser:

```
http://localhost:6080/vnc.html?autoconnect=1&resize=scale
```

The VNC password is generated at install time and stored in `/opt/mt-docker/.env`.
Change it anytime via menu **6 → 6 (Change VNC password)**.

---

## Configuration (`.env`)

The script works **without any `.env`** — it uses the official MetaQuotes installers by default.
If you want to customize, copy the template:

```bash
cp .env.example .env
```

| Variable | Default | Description |
|---|---|---|
| `APP_DIR` | `/opt/mt-docker` | Base install directory on the host |
| `SSH_PORT` | auto | SSH port used in access instructions |
| `WINE_VERSION` | `10.0.0.0~jammy-1` | Wine version — **keep 10.x** (Wine 11 breaks the official MetaQuotes installer with *"A debugger has been found running"*) |

Example of a custom install:

```bash
sudo env \
  APP_DIR=/opt/mt-docker \
  SSH_PORT=2222 \
  bash install-mt-docker.sh
```

---

## Expert Advisors, Indicators, and Sets

The script creates a **`robos/`** folder next to it (or at `$ROBOS_DIR`):

```
robos/
├── MT4/
│   ├── Experts/        (.ex4 / .mq4)
│   └── Indicators/     (.ex4 / .mq4)
├── MT5/
│   ├── Experts/        (.ex5 / .mq5)
│   └── Indicators/     (.ex5 / .mq5)
└── sets/               (.set — the menu asks which terminal)
```

Send files via `scp` and use **option 3** in the menu:

```bash
scp -P 22 MyRobot.ex5 root@YOUR_IP:/path/robos/MT5/Experts/
```

`.mq4` / `.mq5` (source files) must be compiled in MetaEditor before becoming `.ex4` / `.ex5`.

In the terminal: **Navigator → Expert Advisors / Indicators** → right-click → **Refresh**.
Don't forget to enable **Algo Trading** / **Allow automated trading**.

---

## Backup and Restore

Backups are stored in **`backups/`** (next to `robos/`). Nothing is deleted automatically.

```bash
# Via menu: 6 → 1 (Backup now)
# Via CLI:
sudo bash install-mt-docker.sh backup
```

Restore (menu **6 → 2**) replaces accounts, EAs, and settings — files in `robos/` and `backups/` are **not** touched.

---

## Architecture

```
Linux VPS (headless Ubuntu)
└── Docker
    └── MetaTrader container
        ├── Wine (separate MT4 and MT5 prefixes)
        ├── Xvfb (virtual display :99)
        ├── Fluxbox (lightweight window manager)
        ├── x11vnc (VNC on 127.0.0.1:5900)
        ├── noVNC (web on 127.0.0.1:6080)
        └── Supervisor (manages processes)
```

Persistent data lives in `/opt/mt-docker/data/` (outside the container).

---

## Security

The deployment applies, by default:

- `cap_drop: [ALL]` on the container
- `no-new-privileges: true`
- noVNC/VNC **loopback-only** (accessed via SSH tunnel)
- `.env` with mode `600` owned by `root`
- Container runs as user `mt` (uid 1000), not root

Additional recommendations:

1. Use SSH keys and disable password login.
2. Keep Ubuntu and Docker updated.
3. Firewall allowing only the SSH port.
4. Never commit `.env` (already in `.gitignore`).

---

## Limitations

- **Not affiliated** with MetaQuotes or any broker.
- Only **official MetaQuotes installers** are supported (no broker-specific installers).
- Running the terminal 24/7 **does not guarantee** uptime, correct order execution, or profit.
- Brokers may block or limit access via Wine — test with yours first.
- Running MT4 and MT5 concurrently needs more RAM (≥ 2 GB recommended).

---

## License

Apache License 2.0 — see [LICENSE](LICENSE).

---

## Disclaimer

Software provided **"AS IS"**, without warranties. Automated trading can cause
**total loss of capital**. Use at your own risk. Always test on a demo account.****

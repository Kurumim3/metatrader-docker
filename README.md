# 📊 MetaTrader Docker

### 🚀 Run MetaTrader 4 (MT4) and MetaTrader 5 (MT5) 24/7 on an affordable Linux VPS

Run MT4 and MT5 in Docker on a headless Linux VPS, with browser access through noVNC. No Windows host or full desktop environment required.

Designed for lightweight VPS deployments: **1 GB RAM** is the practical minimum; **2 GB or more** is recommended when running both terminals simultaneously.

> ⚠️ **Independent project.** Not affiliated with MetaQuotes Software Corp. or any broker. Automated trading involves financial risk. Always test with a demo account before using real funds.

## 📋 Requirements

| Item | Recommendation |
|---|---|
| Operating system | Ubuntu Server 22.04 LTS or Debian |
| RAM | 1 GB minimum; 2 GB+ recommended for MT4 + MT5 |
| Disk space | At least 10 GB free |
| Access | Root or sudo privileges |
| Local machine | SSH client and a modern web browser |

## 🚀 Quick Start

```bash
git clone https://github.com/Kurumim3/metatrader-docker.git
cd metatrader-docker

# If the file came from Windows, fix line endings first:
sed -i 's/\r$//' install-mt-docker.sh

sudo bash install-mt-docker.sh
```

After the first run, the shortcut is available:

```bash
sudo mt-menu
```

The installer sets up Docker, configures swap when needed, builds the image, and downloads the **official MetaQuotes installers**. Terminals run inside the container under Wine.

## 🧭 Interactive Menu

| Option | Action |
|---|---|
| **A** | Guided installation (base → MT4/MT5 → EAs) |
| **1** | Install the base environment (Docker, swap, image) |
| **2** | Install or remove MT4 / MT5 |
| **3** | Deploy Expert Advisors, indicators, and `.set` files |
| **4** | Status and diagnostics |
| **5** | Start / stop / restart services |
| **6** | Maintenance: backups, updates, logs, and VNC password |
| **7** | Access instructions (SSH tunnel + noVNC) |
| **0** | Exit |

### Direct Commands

```bash
sudo bash install-mt-docker.sh guided    # Full guided installation
sudo bash install-mt-docker.sh status    # Diagnostics
sudo bash install-mt-docker.sh backup    # Create a backup
```

The aliases `guiada`, `term inais`, and `robos` are also supported if configured by the installer.

## 🌐 Access MetaTrader via noVNC

noVNC is bound to **127.0.0.1** on the VPS and is not exposed directly to the internet. Use an SSH tunnel from your local machine:

```bash
ssh -N -p 22 -L 6080:127.0.0.1:6080 root@YOUR_IP
```

Replace `YOUR_IP` with your VPS address and `22` with your SSH port if different.

Keep the SSH tunnel open, then open this URL in your browser:

<http://localhost:6080/vnc.html?autoconnect=1&resize=scale>

The VNC password is generated during installation and stored in:

```text
/opt/mt-docker/.env
```

Change it anytime via **menu → 6 → Change VNC password**.

> 🔐 Do not expose VNC or noVNC directly to the public internet. Always use the SSH tunnel.

## ⚙️ Configuration (`.env`)

No additional configuration is required for a standard installation. The following variables can be customized:

| Variable | Default | Description |
|---|---|---|
| `APP_DIR` | `/opt/mt-docker` | Base directory on the host |
| `SSH_PORT` | Auto-detected | SSH port shown in access instructions |
| `WINE_VERSION` | `10.0.0.0~jammy-1` | Wine package version |
| `ROBOS_DIR` | Next to the installer | Directory for EAs, indicators, and `.set` files |
| `BACKUP_DIR` | Next to `robos/` | Backup storage directory |

### Custom Installation Example

```bash
sudo env \
  APP_DIR=/opt/mt-docker \
  SSH_PORT=2222 \
  bash install-mt-docker.sh
```

### Wine Compatibility

The project uses **Wine 10.x** as its configured baseline.

In the tested environment, Wine 10 resolves the MetaTrader 5 installer error:

```text
A debugger has been found running in your system
```

Wine 11 can trigger this issue with the official MetaTrader installer in the tested environment. Keep Wine 10 unless you have verified that another version works correctly with the official installers.

## 🤖 Expert Advisors, Indicators, and Sets

On the first run, the script creates a `robos/` directory next to the installer, or uses the directory specified by `ROBOS_DIR` when configured.

```text
robos/
├── MT4/
│   ├── Experts/      # .ex4 / .mq4
│   └── Indicators/   # .ex4 / .mq4
├── MT5/
│   ├── Experts/      # .ex5 / .mq5
│   └── Indicators/   # .ex5 / .mq5
└── sets/             # .set presets for MT4 and MT5
```

1. Copy your files into the appropriate subfolder.
2. Run **menu option 3** to deploy them to the terminal(s).

### Transfer Files from Your Computer

```bash
scp -P 22 MyRobot.ex5 root@YOUR_IP:/path/to/robos/MT5/Experts/
```

Replace the example path with the actual location of your `robos/` directory on the VPS.

### Enable Expert Advisors

After deployment, in MetaTrader:

1. Open **Navigator**.
2. Right-click **Expert Advisors** or **Indicators** and select **Refresh**.
3. Enable **Algo Trading** or the equivalent **Allow automated trading** option.

`.mq4` and `.mq5` files are source files. Compile them in MetaEditor to generate `.ex4` and `.ex5` files before use.

## 💾 Backup and Restore

Backups are stored in the `backups/` directory next to `robos/`. Nothing is deleted automatically.

Create a backup using:

```bash
sudo bash install-mt-docker.sh backup
```

Or use **menu → 6 → Backup now**.

To restore a backup, use **menu → 6 → Restore a backup**.

> ⚠️ **Important:** Restoring a backup replaces current account data, Expert Advisors, and settings for the terminals included in the archive. Back up your current data first if you need to preserve the existing state.

## 🏗️ Architecture

```text
Linux VPS (headless Ubuntu / Debian)
└── Docker
    └── MetaTrader container
        ├── Wine (separate prefixes for MT4 and MT5)
        ├── Xvfb          (virtual display :99)
        ├── Fluxbox       (lightweight window manager)
        ├── x11vnc        (127.0.0.1:5900)
        ├── noVNC         (127.0.0.1:6080)
        └── Supervisor    (process management)
```

Persistent data is stored on the host:

```text
/opt/mt-docker/data/
├── prefix-mt4/
├── prefix-mt5/
├── logs/
└── installers/
```

Docker volumes preserve account data, Expert Advisors, and Wine prefixes across container recreation, according to the configured volume mappings.

## 🔒 Security

The deployment is configured with the following security measures:

- `cap_drop: [ALL]` and `no-new-privileges: true`.
- VNC and noVNC are bound to localhost and accessed through an SSH tunnel.
- The `.env` file is created with permissions `600`.
- The container runs as user `mt` (UID `1000`), not as root.

### Security Recommendations

- Prefer SSH keys and disable password-based SSH login when practical.
- Keep the operating system, Docker, and this project updated.
- Configure the firewall to allow only the ports you need, especially SSH.
- Never commit `.env` or other files containing secrets. Keep them in `.gitignore`.
- Protect VPS credentials and backup archives.

## ⚠️ Limitations

- This is an independent community project and is not affiliated with MetaQuotes or any broker.
- Only the official MetaQuotes installers are supported; broker-branded installers are not supported by the documented setup.
- Running 24/7 does not guarantee uninterrupted connectivity, successful order execution, or profitability.
- Some brokers may restrict or block Wine-based environments. Test compatibility with your broker before relying on this setup.
- Running MT4 and MT5 simultaneously requires additional RAM. **2 GB or more is recommended.**
- VPS, network, platform, and broker outages can interrupt automated trading.
- Automated trading can result in substantial financial losses.

## 📄 License

Licensed under the **Apache License 2.0**. See [`LICENSE`](LICENSE) for details.

## ⚖️ Disclaimer

This software is provided **“AS IS”**, without warranties of any kind, to the extent permitted by law.

Automated trading involves financial risk and can result in the loss of all invested capital. You are solely responsible for your configuration, trading decisions, and use of this software.

**Always test with a demo account before using real funds.**

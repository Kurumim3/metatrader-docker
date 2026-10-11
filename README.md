# 📊 MetaTrader Docker

### 🚀 Run MetaTrader 4 (MT4) and MetaTrader 5 (MT5) 24/7 on an affordable Linux VPS

Run MT4 and MT5 in Docker containers on a Linux VPS, with browser-based access through noVNC. No Windows host or heavy desktop environment required.

Designed for lightweight VPS deployments, with 1 GB of RAM as a minimum starting point and 2 GB or more recommended when running both terminals simultaneously.

> ⚠️ **Independent project.** This project is not affiliated with MetaQuotes Software Corp. or any broker. Automated trading involves financial risk. Always test with a demo account before using real funds.

## 📋 Requirements

| Item | Recommendation |
|---|---|
| Operating system | Ubuntu Server 22.04 LTS or Debian |
| RAM | 1 GB minimum; 2 GB or more recommended |
| Disk space | At least 10 GB free |
| Access | Root or sudo privileges |
| Local computer | SSH client and modern web browser |

## 🚀 Quick Start

Clone the repository and run the installer:

```bash
git clone https://github.com/Kurumim3/metatrader-docker.git
cd metatrader-docker

# If downloaded or edited on Windows, normalize line endings:
sed -i 's/\r$//' install-mt-docker.sh

sudo bash install-mt-docker.sh
```

After the initial setup, the `mt-menu` command becomes available:

```bash
sudo mt-menu
```

The installer automates environment setup and downloads the official MetaTrader installers from MetaQuotes. The terminals run inside a Docker container using Wine.

## 🧭 Interactive Menu

| Option | Action |
|---|---|
| `G` | Guided installation (base environment → MT4/MT5 → EAs) |
| `1` | Install the base environment (Docker, swap, image creation) |
| `2` | Install or remove MT4 and MT5 |
| `3` | Deploy Expert Advisors, indicators, and `.set` files |
| `4` | Check status and diagnostics |
| `5` | Start, stop, or restart services |
| `6` | Maintenance: backups, updates, logs, and VNC password |
| `7` | Access instructions and SSH tunnel setup |
| `0` | Exit |

The guided installation walks you through the setup step by step.

### Direct Commands

You can also run common operations directly:

```bash
# Guided installation
sudo bash install-mt-docker.sh guiada

# Diagnostics
sudo bash install-mt-docker.sh status

# Create a backup
sudo bash install-mt-docker.sh backup
```

## 🌐 Access MetaTrader Through noVNC

By default, noVNC is bound to `127.0.0.1` on the VPS and is not directly exposed to the internet. Access it securely through an SSH tunnel.

On your **local computer**, run:

```bash
ssh -N -p 22 -L 6080:127.0.0.1:6080 root@YOUR_IP
```

Replace `YOUR_IP` with your VPS IP address and `22` with your SSH port if it is different.

Keep the SSH session open, then visit this address in your browser:

<http://localhost:6080/vnc.html?autoconnect=1&resize=scale>

The VNC password is generated during installation and stored in:

```text
/opt/mt-docker/.env
```

You can change the VNC password at any time through the interactive menu: **Option 6 → Change VNC password**.

> 🔐 Do not expose VNC or noVNC directly to the public internet. Use the SSH tunnel.

## ⚙️ Configuration (`.env`)

No additional configuration is required for a standard installation. The installer uses the official MetaQuotes installers by default.

To customize the installation, create a `.env` file from the example:

```bash
cp .env.example .env
```

Available variables:

| Variable | Default | Description |
|---|---|---|
| `APP_DIR` | `/opt/mt-docker` | Base installation directory on the host |
| `SSH_PORT` | `auto` | SSH port used in access instructions |
| `WINE_VERSION` | `10.0.0.0~jammy-1` | Wine package version used by the environment |

### Wine Compatibility

This project uses **Wine 10.x** as its configured baseline. In the tested environment, Wine 10 resolves the MetaTrader 5 installer error:

`A debugger has been found running in your system`

Wine 11 is not the configured version for this setup because it triggers that installer issue in the tested environment. Keep the Wine version aligned with the project's tested configuration unless you have verified compatibility with another version.

### Custom Installation Example

```bash
sudo env \
  APP_DIR=/opt/mt-docker \
  SSH_PORT=2222 \
  bash install-mt-docker.sh
```

Adjust the values to match your environment.

## 🤖 Expert Advisors, Indicators, and Presets

The installer creates a `robos/` directory alongside the project or uses the directory configured through `ROBOS_DIR`, if supported by your setup.

Expected directory structure:

```text
robos/
├── MT4/
│   ├── Experts/        # .ex4 / .mq4
│   └── Indicators/     # .ex4 / .mq4
├── MT5/
│   ├── Experts/        # .ex5 / .mq5
│   └── Indicators/     # .ex5 / .mq5
└── sets/               # .set presets
```

Use **menu option 3** to deploy your files to the appropriate terminal.

You can also transfer files with `scp`. For example:

```bash
scp -P 22 MyRobot.ex5 root@YOUR_IP:/path/robos/MT5/Experts/
```

Replace the example path with the actual location of your `robos/` directory on the VPS.

### Source Files and Compiled Files

- `.mq4` and `.mq5` are source files.
- `.ex4` and `.ex5` are compiled files used by the terminals.

Compile source files in MetaEditor before using the resulting executable files.

After deployment, in MetaTrader:

1. Open the **Navigator** panel.
2. Right-click **Expert Advisors** or **Indicators**.
3. Select **Refresh**.
4. Enable **Algo Trading** or the equivalent automated-trading permission required by your terminal and EA.

Check the EA's individual settings and your broker's requirements before allowing live trading.

## 💾 Backup and Restore

Backups are stored in the `backups/` directory alongside `robos/`. Existing backups are not automatically deleted.

Create a backup through **menu option 6 → Backup**, or run:

```bash
sudo bash install-mt-docker.sh backup
```

Use **menu option 6 → Restore** to restore a backup.

> ⚠️ **Important:** Restoring a backup can replace existing account data, Expert Advisors, and configuration files. Back up your current data before restoring. Verify the restore behavior and target paths before proceeding.

## 🏗️ Architecture

```text
Linux VPS (headless Ubuntu)
└── Docker
    └── MetaTrader container
        ├── Wine (separate MT4 and MT5 prefixes)
        ├── Xvfb (virtual display :99)
        ├── Fluxbox (lightweight window manager)
        ├── x11vnc (VNC on 127.0.0.1:5900)
        ├── noVNC (web access on 127.0.0.1:6080)
        └── Supervisor (process management)
```

Persistent data is stored on the host under:

```text
/opt/mt-docker/data/
```

This allows the relevant data to persist outside the container across container recreation, according to the project's volume configuration.

## 🔒 Security

The deployment is designed with several security measures:

- Docker capabilities are dropped with `cap_drop: [ALL]`.
- `no-new-privileges` is enabled for the container.
- VNC and noVNC are bound to loopback interfaces and accessed through an SSH tunnel.
- The `.env` file is intended to use permissions `600` and be owned by `root`.
- The container runs as the `mt` user (UID `1000`), rather than as root.

### Additional Recommendations

- Use SSH keys and disable password-based SSH login where practical.
- Keep Ubuntu, Docker, and the project updated.
- Configure the firewall to allow only the ports you actually need, especially SSH.
- Never commit `.env` or other files containing passwords or secrets. Keep them excluded through `.gitignore`.
- Protect your VPS credentials and backup files.

## ⚠️ Limitations

- This is an independent community project and is not affiliated with MetaQuotes or any broker.
- The project is designed for the official MetaQuotes installers. Broker-specific installers are not supported by the documented setup.
- Running a terminal 24/7 does not guarantee uninterrupted availability, correct order execution, or profitability.
- Brokers may restrict or block access through Wine. Test compatibility with your broker before relying on the setup.
- Running MT4 and MT5 simultaneously requires more resources. At least 2 GB of RAM is recommended for this configuration.
- VPS, network, broker, and platform outages can interrupt automated trading.
- Automated trading can cause substantial financial losses.

## 📄 License

This project is licensed under the **Apache License 2.0**. See [`LICENSE`](LICENSE) for details.

## ⚖️ Disclaimer

This software is provided **"AS IS"**, without warranties or guarantees of any kind, to the extent permitted by law.

Automated trading involves financial risk and can result in the loss of all invested capital. You are responsible for your own configuration, trading decisions, and use of this software.

**Always test with a demo account before using real funds.**

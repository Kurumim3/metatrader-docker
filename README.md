# MetaTrader 4/5 in Docker with noVNC

Run MetaTrader 4 (MT4) and MetaTrader 5 (MT5) on an Ubuntu/Debian VPS without a full desktop environment. Docker, Wine and noVNC provide a lightweight browser-based desktop.

> **Disclaimer:** This independent project is not affiliated with MetaQuotes or any broker. Automated trading involves financial risk. Test with a demo account before using real funds.

## Features

- **MT4 and MT5:** Install either terminal or both.
- **Management menu:** Manage terminals, EAs, indicators, `.set` files, services and logs.
- **Wine selection:** Wine 10 is recommended; Wine 11.20 is available with possible installer compatibility issues.
- **Browser access:** Connect through noVNC using an SSH tunnel.
- **Backups and restore:** Create, validate, restore and manage backups before maintenance or updates.
- **Cloudflare WARP:** Optional connectivity modes for download issues or routing MT traffic through WARP.
- **Resource management:** Keep MT4 stopped while installing MT5 to reduce memory pressure.
- **Timezone configuration:** Set the environment timezone.

## Requirements

| Item | Recommendation |
|---|---|
| OS | Ubuntu Server 22.04 LTS or Debian |
| RAM | 1 GB minimum; 2 GB+ recommended for MT4 and MT5 |
| Disk | At least 10 GB free |
| Access | Root or sudo |
| Local machine | SSH client and modern browser |
| Docker Compose | 2.24.4+ required for Full WARP mode |

Internet access is required for setup and terminal downloads. Docker Compose is installed by the script when needed.

## Quick Start

Clone the repository and enter the project directory:

```bash
git clone https://github.com/Kurumim3/metatrader-docker.git
cd metatrader-docker
```

If the installation script was transferred from Windows, convert its line endings before running it:

```bash
sed -i 's/\r$//' install-mt-docker.sh
```

Run the installer:

```bash
sudo bash install-mt-docker.sh
```

After the initial setup, open the interactive management menu at any time with:

```bash
sudo mt-menu
```

## Command-line usage

```bash
sudo bash install-mt-docker.sh [--lang en|pt] <command>
```

| Command | Purpose |
|---|---|
| `guided` | Guided installation |
| `base` | Install base environment |
| `terminals` | Install or remove MT4/MT5 |
| `bots` | Copy EAs, indicators and `.set` files |
| `status` | Show status and diagnostics |
| `backup` | Create a backup |
| `language` | Change interface language |
| `warp` | Manage Cloudflare WARP |
| `help` | Show help |

Run without a command to open the interactive menu.

## Management menu

| Option | Action |
|---|---|
| `A` | Guided installation |
| `1` | Base environment |
| `2` | Install/remove MT4 and MT5 |
| `3` | Deploy EAs, indicators and `.set` files |
| `4` | Status, backups, updates, logs, password, timezone, WARP and uninstall |
| `5` | Start, stop or restart services |
| `6` | Access instructions |
| `L` | Change language |
| `0` | Exit |

## MT4, MT5 and Wine

Use menu option `2` to install MT4, MT5 or both. When installing both, MT4 is kept stopped while MT5 is installed to reduce memory pressure.

The script uses official MetaQuotes installers when a suitable local installer is not provided. A broker installer can be placed in `data/installers/` and will be preferred.

- **Wine 10:** Recommended for compatibility with the official MetaQuotes installer.
- **Wine 11.20 (development):** Newer, but the official installer may fail with “A debugger has been found running”.

The selected version is stored in `$APP_DIR/.env` and applied during the next image build.

## Expert Advisors, indicators and `.set` files

Place files in the project’s `EAs/` directory, then run menu option `3` to copy them into MetaTrader.

```text
EAs/
├── MT4/Experts
├── MT4/Indicators
├── MT5/Experts
├── MT5/Indicators
└── sets/
```

Use `.ex4`/`.mq4` files for MT4, `.ex5`/`.mq5` files for MT5, and `.set` files for settings. After deployment, confirm that files appear in MetaTrader and enable automated trading when appropriate.

The default bot directory is `$APP_DIR/EAs`. Custom locations can be configured with `ROBOS_DIR` and `BACKUP_DIR`.

## Access through noVNC

noVNC is bound to `127.0.0.1` on the VPS. Connect through an SSH tunnel rather than exposing the interface directly.

On your local computer:

```bash
ssh -N -p 22 -L 6080:127.0.0.1:6080 root@YOUR_IP
```

Replace `YOUR_IP`, the SSH port and username as needed. Keep the tunnel running, then open:

```text
http://localhost:6080/vnc.html?autoconnect=1&resize=scale
```

Enter the VNC password when prompted. Menu option `6` displays the access instructions and current password.

## Cloudflare WARP (optional)

Manage WARP from menu option `4 → 9`, or with the `warp` command.

- **SOCKS proxy:** Provides a local SOCKS5 proxy, mainly for downloading installers when MetaQuotes blocks the VPS IP.
- **Full WARP mode:** Routes all traffic from the MT container—including broker connections and downloads—through Cloudflare WARP.

Full WARP mode requires Docker Compose `2.24.4+` and adds roughly 100–250 MB of RAM. It can increase latency, and some brokers may not accept shared Cloudflare exit IPs. Check broker requirements before using it with live accounts. WARP can help with some connectivity issues but does not guarantee a fix.

## Backups, restore and updates

Open menu option `4` for maintenance:

- Create or restore backups.
- Delete old backups.
- Update the environment (backup, rebuild and restart).
- View live logs and resource usage.
- Change the VNC password or timezone.
- Manage WARP or uninstall the environment.

Backups are stored in `$BACKUP_DIR` (default: `backups/` next to `EAs/`). Archives are checked for integrity and include a `.sha256` checksum. Restore includes rollback if copying fails.

Set `BACKUP_KEEP=N` to retain only the latest `N` backups; by default, all backups are kept. For important setups, keep an independent copy of backups and verify that restoration works.

## Configuration and data locations

The default application directory is `/opt/mt-docker`.

| Variable | Default | Purpose |
|---|---|---|
| `APP_DIR` | `/opt/mt-docker` | Application directory |
| `ROBOS_DIR` | `<project>/EAs` | EA, indicator and `.set` files |
| `BACKUP_DIR` | `<project>/backups` | Backup location |
| `SSH_PORT` | `22` (auto-detected) | Used in access instructions |

Wine settings and the VNC password are stored in `$APP_DIR/.env`. The selected bot and backup paths are remembered in `$APP_DIR/.robos_dir` and `$APP_DIR/.backup_dir`.

## Uninstall

Use menu option `4 → U`. The script removes the container and image and lets you choose whether to keep or delete data. Data, EAs and backups are kept by default. To delete everything, enter `APAGAR` in Portuguese or `DELETE` in English when prompted.

## License

Licensed under the Apache License 2.0. See `LICENSE` for details.

## Disclaimer

This project is an independent environment-management tool for running MetaTrader on Linux. It is not financial advice and does not guarantee trading performance, profitability or uninterrupted operation. MetaTrader 4 and MetaTrader 5 are products of MetaQuotes Software Corp.; all trademarks belong to their respective owners.

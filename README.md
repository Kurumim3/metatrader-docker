# MetaTrader 4/5 in Docker with noVNC

Install and manage MetaTrader 4 (MT4) and MetaTrader 5 (MT5) on an Ubuntu/Debian VPS without a desktop environment. The project uses Docker, Wine and noVNC to provide a lightweight, browser-based desktop for the terminals.

## Features

- **MT4 and MT5 support** — install either terminal or both.
- **Interactive management menu** — install/remove terminals, manage Expert Advisors (EAs), indicators and `.set` files, view status and logs, and control the services.
- **Wine version selection** — choose the supported Wine version during setup, including Wine 11.20 where offered by the installer.
- **Browser-based access** — view the terminal desktop through noVNC.
- **Resource-conscious operation** — MT4 can be kept stopped while MT5 is installed to reduce memory pressure on smaller VPS plans.
- **Automated backup workflow** — create backups before updates, make manual backups, and restore or remove existing backups from the maintenance menu.
- **Cloudflare WARP integration** — optionally manage WARP from the menu. It can help when the VPS network or public IP has trouble reaching MetaQuotes download servers. WARP is a connectivity option, not a guarantee that every network issue will be resolved.
- **Timezone configuration** — set the timezone used by the environment.

## Requirements

- Ubuntu or Debian VPS.
- Root or `sudo` access.
- Docker and Docker Compose v2 (the installer can install Docker when needed).
- Internet access during setup and when downloading terminal installers.
- Recommended: 1–2 GB RAM for a lightweight setup. Running both terminals and additional EAs may require more memory.

## Installation

Run the installer as root or with `sudo`:

```bash
sudo bash install-mt-docker.sh
```

Follow the interactive menu. The guided installation helps configure the base environment and choose the Wine version.

After the initial setup, the menu shortcut is available:

```bash
sudo mt-menu
```

The script also supports command-line actions such as `base`, `terminals`, `bots`, `status`, `backup` and `language`. Run the script with the relevant command or consult its built-in menu for the available options.

## Installing MT4 and MT5

Use the terminal installation option to install MT4, MT5, or both. If both are selected, the installer can install them sequentially to reduce memory pressure during installation.

The installer uses official MetaQuotes installers when a suitable local installer is not supplied.

## Expert Advisors, Indicators and Set Files

The project creates an `EAs` directory inside the project folder. Use the bot-management option to copy your files into the appropriate locations:

```text
MT4/Experts       MT4 Expert Advisors (.ex4 / .mq4)
MT4/Indicators    MT4 indicators
MT5/Experts       MT5 Expert Advisors (.ex5 / .mq5)
MT5/Indicators    MT5 indicators
sets/             .set files for MT4 and MT5
```

After copying files, open the relevant terminal and confirm that the EA or indicator appears in MetaTrader. Check that any required dependencies and input settings are present before running it on a live account.

## Accessing MetaTrader

The desktop is provided through noVNC in a web browser. Use the access information shown by the installer or the menu, and follow its SSH-tunnel instructions when connecting remotely.

The default configuration binds noVNC to the local host interface rather than publishing it directly to the internet.

## Backups, Restore and Updates

The maintenance menu includes options to:

- Create a backup on demand.
- Restore a previously created backup.
- Delete backups that are no longer needed.
- Update the environment by creating a backup, rebuilding the Docker image and restarting the service.

**Why backups help:** a recent backup provides a recovery point for terminal data and configuration if an update or maintenance operation causes problems. Keeping backups separate from the running container also makes recovery easier if the container or image needs to be rebuilt.

Backups should not be treated as a substitute for an independent copy. For important trading setups, periodically copy backup files to another server or storage location and verify that a restore works.

Before updating, make sure there is enough disk space for the new backup. Avoid deleting the only known-good backup until the updated environment has been checked.

## Cloudflare WARP

Cloudflare WARP can be managed from the **Status & Maintenance** menu. It is optional.

WARP may help when a VPS provider's network route or public IP has difficulty reaching MetaQuotes download servers. The installer can offer to enable it during base setup, and the maintenance menu provides controls for managing it later.

WARP changes the network path used by the environment, so its effect depends on the VPS network and the destination service. If downloads already work reliably, enabling WARP may not provide a benefit. After changing WARP settings, retry the affected download and review the logs if the problem continues.

## Status and Maintenance

The management menu provides tools for checking the container and terminal status, viewing live logs and resource usage, changing the VNC password, adjusting the timezone, managing WARP, and starting, stopping or restarting services.

If something fails, check the status first, then review the relevant logs before repeating an installation or update.

## Configuration and Data Locations

The main application directory defaults to:

```text
/opt/mt-docker
```

The installer supports configuration for the application directory, bot directory, backup directory and SSH port. These values can be supplied through the environment or a `.env` file, as supported by the script.

The selected Wine version is stored in the application's `.env` file. Check the configured paths in your environment before manually moving or deleting files.

## Uninstalling

Use the uninstall option in the management menu. Review the displayed actions carefully and make sure any required backups have been copied elsewhere before removing the environment.

## Disclaimer

This project is an environment-management tool and is not financial advice. Trading involves risk, and automated trading systems can lose money. Test terminals, EAs and settings in a demo environment before using a live account.

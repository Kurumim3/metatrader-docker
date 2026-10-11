# 📊 MetaTrader Docker

### 🚀 Run MetaTrader 4 (MT4) and MetaTrader 5 (MT5) 24/7 on an Affordable Linux VPS

Run MT4 and MT5 in Docker on a headless Linux VPS, with browser-based access through noVNC. No Windows host or full desktop environment required.

Designed for lightweight VPS deployments: **1 GB RAM is the practical minimum**, while **2 GB or more is recommended** when running both terminals simultaneously.

> ⚠️ **Independent project.** This project is not affiliated with MetaQuotes Software Corp. or any broker. Automated trading involves financial risk. Always test with a demo account before using real funds.

---

## 📋 Requirements

| **Item** | **Recommendation** |
| :--- | :--- |
| Operating system | Ubuntu Server 22.04 LTS or Debian |
| RAM | 1 GB minimum; 2 GB or more recommended for MT4 + MT5 |
| Disk space | At least 10 GB free |
| Access | Root or sudo privileges |
| Local machine | SSH client and a modern web browser |

---

## 🚀 Quick Start

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

The installer automates the initial setup, including Docker installation, swap configuration when needed, Docker image building, and environment management. The trading terminals run inside the container using Wine.

> 💡 **MT4 and MT5 installation:** The interactive menu provides options to install MT4 and MT5 inside the Docker container using the project's supported installation workflow. The terminals do not need to be installed manually on the Linux host.

---

## 🌎 Language Support

The interactive menu and installation messages support:

- 🇺🇸 **English**
- 🇧🇷 **Brazilian Portuguese (pt-BR)**

You can select your preferred language during the initial setup or change it at any time through the interactive menu using option **L**.

---

## 🧭 Interactive Menu

Launch the management menu with:

```bash
sudo mt-menu
```

| **Option** | **Action** |
| :---: | :--- |
| **A** | Guided installation (base environment → MT4/MT5 → Expert Advisors) |
| **1** | Install the base environment (Docker, swap, and image) |
| **2** | Install or remove MT4 / MT5 |
| **3** | Deploy Expert Advisors (EAs), indicators, and `.set` files |
| **4** | View status and run diagnostics |
| **5** | Start, stop, or restart services |
| **6** | Maintenance: backups, updates, logs, and VNC password |
| **7** | View access instructions (SSH tunnel + noVNC) |
| **L** | Change language (English / Português) |
| **0** | Exit |

---

## 🌐 Accessing MetaTrader Through noVNC

For security, noVNC is bound to `127.0.0.1` on the VPS and is not intended to be exposed directly to the public internet.

### 1. Create an SSH Tunnel

From your local computer, open a terminal and run:

```bash
ssh -N -p 22 -L 6080:127.0.0.1:6080 root@YOUR_IP
```

Replace `YOUR_IP` with your VPS IP address and `22` with your SSH port if it is different.

If you connect using a non-root account, replace `root` with your SSH username.

### 2. Open noVNC in Your Browser

Keep the SSH tunnel running and open the following URL in your local browser:

[http://localhost:6080/vnc.html?autoconnect=1&resize=scale](http://localhost:6080/vnc.html?autoconnect=1&resize=scale)

You can then access the graphical environment through your browser.

> 🔐 **Security warning:** Do not expose VNC or noVNC directly to the public internet. Use an SSH tunnel to access the interface securely.

---

## 📄 License

This project is licensed under the **Apache License 2.0**.

See the [LICENSE](LICENSE) file for the full license text.

---

## ⚠️ Disclaimer

This project is an independent, community-developed solution for running MetaTrader terminals in a Docker container on Linux.

MetaTrader 4 and MetaTrader 5 are products of MetaQuotes Software Corp. All trademarks belong to their respective owners.

This project does not provide financial advice or guarantee trading performance, profitability, or uninterrupted operation. You are responsible for your trading decisions, server configuration, and security.

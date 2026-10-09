# 📊 MetaTrader Docker

🚀 Run MetaTrader 4 (MT4) & MetaTrader 5 (MT5) 24/7 on Headless Ubuntu Server

A lightweight, production-ready solution tailored specifically for **minimal Ubuntu Server installations without a desktop environment (headless / CLI-only)**. It creates a virtual display layer inside Docker (Xvfb + Fluxbox + noVNC), allowing you to run, manage, and access Windows trading terminals directly from your web browser with zero GUI packages installed on the host VPS.

Manage base setup, terminal installations, Expert Advisors (EAs), custom indicators, background services, automated backups, and runtime logs through a single interactive shell script.

## ✨ Highlights

* ⚡ **Lightweight Deployment:** Designed for low-resource VPS environments.
* 🖥️ **Browser-Based GUI:** Access the desktop through noVNC.
* 🐳 **Automated Setup:** Simplifies deployment using Docker and Wine.
* 💾 **Persistent Environments:** Keeps MT4 and MT5 data across container restarts.
* 🎮 **Interactive Management Menu:** Manage installation and everyday operations from one place.

## 📋 Features

* 🚀 **One-Command Installer:** Sets up Docker, configures swap, generates project files, builds the image, and starts the container.
* 📈 **MT4 & MT5 Support:** Install and run both MetaTrader terminals in separate Wine environments.
* 🌐 **Web-Based Desktop:** Access the graphical interface directly from your browser using noVNC.
* 📊 **VPS Resource Optimization:** Configurable memory, CPU, swap, and container limits.
* 📂 **Persistent Data:** Stores terminal environments and logs in mounted directories.
* 🤖 **Expert Advisor Deployment:** Install compiled `.ex4` and `.ex5` files through the interactive menu.
* ⚙️ **Service Supervision:** Manage terminal processes with automatic restart support.
* 🔍 **Integrated Diagnostics:** Check container status, running processes, resource usage, and logs.
* 🛠️ **Maintenance Tools:** Access backups, updates, service management, and log inspection from the menu.
* 🔒 **Security-Focused Configuration:** Reduced container privileges and SSH-tunneled access to noVNC.

## 💻 System Requirements

| **Requirement**      | **Details**                                             |
| -------------------- | ------------------------------------------------------- |
| **Operating System** | Ubuntu 22.04 LTS recommended                            |
| **Privileges**       | Root access or `sudo` permissions                       |
| **RAM**              | 1 GB minimum; 2 GB recommended for MT4 and MT5 together |
| **Disk Space**       | At least 10 GB free                                     |
| **Network**          | Internet connection for installation and downloads      |
| **Local Access**     | SSH client and a modern web browser                     |

## ⚡ Quick Start

### Step 1: Clone the Repository

```bash
git clone https://github.com/Kurumim3/metatrader-docker.git
cd metatrader-docker
```

### Step 2: Run the Installer

If the script has Windows-style line endings (`CRLF`), convert it first:

```bash
sed -i 's/\r$//' install-mt-docker.sh
```

Start the interactive installer:

```bash
sudo bash install-mt-docker.sh
```

### Step 3: Configure via the Interactive Menu

Follow the on-screen options:

| **Option** | **Action / Description**               |
| ---------- | -------------------------------------- |
| **1**      | Install the base environment           |
| **2**      | Install MT4, MT5, or both              |
| **3**      | Install Expert Advisors and indicators |
| **4**      | Check status and diagnostics           |
| **5**      | Start, stop, or restart services       |
| **6**      | Access maintenance tools               |
| **0**      | Exit                                   |

> 💡 **Note:** The base installation prepares Docker, configures swap space, generates configuration files, builds the container image, and starts the required services.

## ⚙️ Configuration

The installer supports environment variables to customize your deployment:

| **Variable**   | **Default**                  | **Description**                                |
| -------------- | ---------------------------- | ---------------------------------------------- |
| `APP_DIR`      | `/opt/mt-docker`             | Application installation directory             |
| `SSH_PORT`     | Auto-detected, fallback `22` | SSH port used in access instructions           |
| `ZIP_URL`      | Configured download URL      | Source URL for the terminal installer archive  |
| `ZIP_PASSWORD` | Configured default           | Password used to extract the installer archive |

### Example Custom Installation

```bash
sudo env \
  APP_DIR=/opt/mt-docker \
  SSH_PORT=22 \
  bash install-mt-docker.sh
```

> 🔧 **Tip:** If you need to use a different terminal installer archive, configure `ZIP_URL` and `ZIP_PASSWORD` before running the installer.

## 🌐 Accessing MetaTrader via noVNC

After the base installation, the installer displays the VNC password and the SSH tunnel command.

### 1. Open an SSH Tunnel

Run this command on your **local computer**, replacing `SSH_PORT` and `VPS_IP` with your VPS details:

```bash
ssh -N -p SSH_PORT \
  -L 6080:127.0.0.1:6080 \
  root@VPS_IP
```

> ⚠️ **Important:** Keep the SSH session open while using the browser interface.

### 2. Open the Browser Interface

Navigate to:

```text
http://localhost:6080/vnc.html?autoconnect=1&resize=scale
```

Enter the VNC password provided during installation.

> 🔒 **Security Note:** noVNC is bound to the VPS loopback interface by default. Access it through the SSH tunnel instead of exposing port `6080` directly to the internet.

## 🤖 Installing Expert Advisors and Indicators

Deploy your compiled trading robots and custom indicators through the interactive menu:

1. Complete the base installation using **Option 1**.
2. Install MT4 and/or MT5 using **Option 2**.
3. Copy your compiled `.ex4` and `.ex5` files into the same directory as `install-mt-docker.sh`.
4. Select **Option 3 — Install Robots/Indicators**.
5. Choose the appropriate terminal and file type when prompted.

> 📝 **Tip:** Source files (`.mq4` and `.mq5`) must be compiled in MetaEditor before installation. After installation, find your files in MetaTrader under **Navigator → Experts** or **Navigator → Indicators**.

## 🏛️ Architecture Overview

The project combines containerization, Windows compatibility, process supervision, and browser-based desktop access:

```text
Linux VPS
└── Docker
    └── MetaTrader Container
        ├── Wine
        │   ├── MT4 Environment
        │   └── MT5 Environment
        ├── Xvfb — Virtual Display
        ├── Fluxbox — Window Manager
        ├── x11vnc — VNC Server
        ├── noVNC — Browser Access
        └── Supervisor — Process Management
```

> 💾 *Terminal environments and logs are persisted outside the container using mounted volumes.*

## 🛠️ Management & Diagnostics

The interactive menu provides access to common administration tasks:

* 🔍 Check container and terminal status.
* 📊 Inspect running processes and resource usage.
* 🔄 Start, stop, and restart services.
* 💾 Access backup and maintenance tools.
* 📜 Update components and inspect application logs.

### Direct Docker Commands

```bash
cd /opt/mt-docker

docker compose ps
docker compose logs --tail 100
docker stats
```

## 🛡️ Security Best Practices

The project includes several security measures:

* 🛡️ Unnecessary Linux capabilities are dropped.
* 🔒 The `no-new-privileges` flag is enabled.
* 🌐 VNC access is restricted to the loopback interface by default.
* 🔑 VNC credentials are stored in `.env` with restrictive file permissions.
* 📂 Persistent application data is separated from the container image.

**Recommended Practices:**

* Keep `.env` files and credentials out of public version control.
* Use SSH key authentication where possible.
* Keep your VPS operating system and Docker installation updated.
* Never expose noVNC or management ports directly to the public internet.
* Protect trading account credentials and backup files.

## 📜 License

Licensed under the **Apache License 2.0**. See the [`LICENSE`](LICENSE) file for details.

## ⚠️ Disclaimer

*This project is an unofficial solution and is not affiliated with, endorsed by, or supported by MetaQuotes or any broker.*

> 💡 **Financial Risk Warning:** This software is provided *"AS IS"*, without warranties of any kind. Trading involves financial risk and can result in the loss of capital. Always test your strategies in a demo account before trading with real funds.

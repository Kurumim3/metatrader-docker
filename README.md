# 📊 MetaTrader Docker

> 🚀 Run MetaTrader 4 (MT4) and MetaTrader 5 (MT5) 24/7 on a Headless Ubuntu Server.

A lightweight, Docker-based solution for running Windows trading terminals on Linux VPS environments without requiring a desktop environment on the host.

**MetaTrader Docker** combines Wine, Xvfb, Fluxbox, x11vnc, noVNC, and Supervisor to provide a virtual desktop, browser-based access, process management, and persistent terminal data in a single containerized environment.

Manage installation, terminal provisioning, Expert Advisors (EAs), custom indicators, diagnostics, backups, and maintenance through an interactive shell menu.

---

## 💡 Why MetaTrader Docker?

Running Windows-based trading terminals on Linux can involve complex setup procedures, desktop dependencies, and limited server resources. MetaTrader Docker simplifies this process by integrating the essential components into a unified deployment workflow.

### ⭐ Key Differentiators

* **🔄 Dual Terminal Support:** Run MetaTrader 4 (32-bit) and MetaTrader 5 (64-bit) in separate Wine prefixes, independently or simultaneously.
* **⚡ Lightweight Desktop Stack:** Uses Xvfb and Fluxbox instead of a full desktop environment, making it suitable for resource-constrained VPS deployments.
* **🤖 Automated Installation:** Streamlines terminal installation and process initialization through an interactive management script.
* **🛡️ Managed Shutdown:** Coordinates process termination to help terminals close cleanly and reduce the risk of data loss.
* **🔒 Secure Remote Access:** Provides browser-based access through noVNC over an SSH tunnel, without requiring direct public exposure of the VNC service.
* **🎮 All-in-One CLI Manager:** Simplifies deployment, service operations, diagnostics, backups, and maintenance through a single interactive menu.

---

## ✨ Highlights

* 🐳 **Docker-Based Deployment:** Package the trading environment in a manageable container.
* 🖥️ **Browser-Based GUI:** Access the virtual desktop from a modern web browser.
* 📈 **MT4 & MT5 Compatibility:** Support legacy 32-bit and modern 64-bit terminal environments.
* 💾 **Persistent Storage:** Keep terminal data and configurations outside the container using mounted volumes.
* 🤖 **EA & Indicator Deployment:** Install compiled trading algorithms and custom indicators through the management menu.
* 📊 **Resource Management:** Configure memory, swap, CPU, and process limits according to the deployment environment.
* 🔍 **Integrated Diagnostics:** Inspect container status, running processes, resource usage, and logs.
* 🛠️ **Maintenance Tools:** Simplify container operations, backups, and troubleshooting.

---

## 📋 Features

| Feature                   | Description                                                                       |
| :------------------------ | :-------------------------------------------------------------------------------- |
| 🚀 Automated Installer    | Prepares the environment, configures Docker, and builds and starts the container. |
| 📈 MT4 & MT5              | Supports separate Wine prefixes for each terminal.                                |
| 🌐 noVNC Access           | Provides browser-based access to the virtual desktop.                             |
| 🪶 Lightweight GUI        | Uses Xvfb and Fluxbox instead of a full desktop environment.                      |
| 💾 Persistent Data        | Stores terminal environments and other configured data in host-mounted volumes.   |
| 🤖 EA & Indicator Manager | Deploys compiled `.ex4` and `.ex5` files.                                         |
| ⚙️ Process Supervision    | Uses Supervisor to manage configured background services.                         |
| 🔍 Diagnostics            | Provides status information, resource monitoring, and log inspection.             |
| 🛠️ Maintenance           | Offers backup and container management utilities.                                 |
| 🔒 Security Controls      | Supports reduced container privileges and loopback-only remote desktop access.    |

---

## 💻 System Requirements

| Requirement      | Recommendation                                                                 |
| :--------------- | :----------------------------------------------------------------------------- |
| Operating System | Ubuntu Server 22.04 LTS                                                        |
| Permissions      | Root access or `sudo` privileges                                               |
| RAM              | 1 GB minimum; 2 GB or more recommended                                         |
| Disk Space       | At least 10 GB of free space                                                   |
| Network          | Outbound internet access for installation and downloads                        |
| Local Computer   | SSH client and a modern web browser                                            |
| Software         | Docker Engine and Docker Compose, installed by the setup process if configured |

**Resource note:** Actual RAM, CPU, and storage requirements depend on the number of terminals, charts, indicators, Expert Advisors, and trading workloads. Additional memory may be necessary for running MT4 and MT5 concurrently.

---

## ⚡ Quick Start

### 1. Clone the Repository

```bash
git clone https://github.com/Kurumim3/metatrader-docker.git
cd metatrader-docker
```

### 2. Run the Installer

If the installer contains Windows-style line endings (`CRLF`), normalize the file first:

```bash
sed -i 's/\r$//' install-mt-docker.sh
```

Launch the interactive installer:

```bash
sudo bash install-mt-docker.sh
```

### 3. Configure the Environment

Follow the on-screen menu to complete the initial setup and manage your terminals.

| Option | Action                                                                       |
| :----: | :--------------------------------------------------------------------------- |
|  **1** | Base installation: Docker, swap, system tuning, permissions, and image build |
|  **2** | Install MT4, MT5, or both                                                    |
|  **3** | Install Expert Advisors and custom indicators                                |
|  **4** | Status and diagnostics                                                       |
|  **5** | Service operations: start, stop, and restart                                 |
|  **6** | Maintenance: backups, rebuilds, and logs                                     |
|  **0** | Exit                                                                         |

> 💡 **Tip:** Start with Option 1 to prepare the environment. Then install the required terminal(s) using Option 2.

*Menu descriptions are based on the documented installer workflow. Confirm that the option numbers match the current script before publishing changes.*

---

## ⚙️ Configuration

The installer supports environment variables for customizing the deployment.

| Variable       | Default               | Description                                |
| :------------- | :-------------------- | :----------------------------------------- |
| `APP_DIR`      | `/opt/mt-docker`      | Installation directory on the host         |
| `SSH_PORT`     | `22` or auto-detected | SSH port used in connection instructions   |
| `ZIP_URL`      | Preconfigured URL     | Download URL for the installer archive     |
| `ZIP_PASSWORD` | `123456`              | Password used to extract the setup archive |

### Custom Installation Example

```bash
sudo env \
  APP_DIR=/opt/mt-docker \
  SSH_PORT=22 \
  bash install-mt-docker.sh
```

**Security note:** If the archive uses a default extraction password, consider replacing it with a strong, unique value when supported by the installer. Do not commit credentials, private URLs, or other secrets to the repository.

---

## 🌐 Accessing MetaTrader via noVNC

After the base installation, use the generated VNC password and connection instructions provided by the installer.

### 1. Create an SSH Tunnel

Run this command on your local computer, replacing `SSH_PORT` and `VPS_IP` with your server's SSH port and IP address.

```bash
ssh -N -p SSH_PORT \
  -L 6080:127.0.0.1:6080 \
  root@VPS_IP
```

Keep the SSH session open while using the browser interface.

### 2. Open the Web Interface

Navigate to:

```text
http://localhost:6080/vnc.html?autoconnect=1&resize=scale
```

Enter the VNC password generated during installation.

The configuration described by this project stores the password in the `.env` file under the installation directory, for example:

```text
/opt/mt-docker/.env
```

### 🔒 Remote Access Security

* Keep the noVNC service bound to `127.0.0.1` on the VPS.
* Access the interface through an SSH tunnel.
* Avoid exposing port `6080` directly to the public internet.
* Protect `.env` and other files containing credentials.
* Prefer SSH key authentication and keep the server and Docker packages updated.

> ⚠️ **Important:** The browser URL uses HTTP on localhost because the SSH tunnel encrypts the connection between your computer and the VPS. Do not expose the underlying web service publicly without an appropriately secured remote-access configuration.

---

## 🤖 Installing Expert Advisors & Indicators

Deploy compiled trading algorithms and custom indicators through the interactive management menu.

1. Complete the base installation using **Option 1**.
2. Install MT4, MT5, or both using **Option 2**.
3. Prepare the compiled files for deployment:

   * `.ex4` for MT4.
   * `.ex5` for MT5.
4. Place the files in the location expected by the installer.
5. Select **Option 3** and follow the prompts to choose the destination terminal and file type.

### Supported File Types

| Extension | Purpose                                                            |
| :-------- | :----------------------------------------------------------------- |
| `.ex4`    | Compiled MetaTrader 4 Expert Advisors and indicators               |
| `.ex5`    | Compiled MetaTrader 5 Expert Advisors and indicators               |
| `.mq4`    | MetaTrader 4 source files; compile in MetaEditor before deployment |
| `.mq5`    | MetaTrader 5 source files; compile in MetaEditor before deployment |

After deployment, locate the files in MetaTrader under **Navigator → Expert Advisors** or **Navigator → Indicators**, as appropriate.

> 📝 **Tip:** Keep backups of your EAs, indicators, set files, and configuration data before performing maintenance or rebuilding the container.

---

## 🏛️ Architecture Overview

MetaTrader Docker combines containerization, Windows application compatibility, virtual display services, and process supervision.

```text
Linux VPS
└── Ubuntu Server (Headless)
    └── Docker
        └── MetaTrader Container
            ├── Wine
            │   ├── MT4 Environment (32-bit)
            │   └── MT5 Environment (64-bit)
            ├── Xvfb
            │   └── Virtual Display
            ├── Fluxbox
            │   └── Lightweight Window Manager
            ├── x11vnc
            │   └── VNC Server
            ├── noVNC
            │   └── Browser-Based Access
            └── Supervisor
                └── Background Process Management
```

### Component Overview

| Component      | Role                                                    |
| :------------- | :------------------------------------------------------ |
| **Docker**     | Provides the containerized runtime environment.         |
| **Wine**       | Runs compatible Windows applications on Linux.          |
| **Xvfb**       | Provides a virtual display without a physical monitor.  |
| **Fluxbox**    | Provides a lightweight window manager.                  |
| **x11vnc**     | Shares the virtual desktop over VNC.                    |
| **noVNC**      | Makes the VNC desktop accessible through a web browser. |
| **Supervisor** | Manages configured application and service processes.   |

Terminal data and other configured files are intended to persist outside the container through host-mounted volumes, including the project's `data/` directory where applicable.

---

## 🛠️ Management & Diagnostics

The interactive management menu is the recommended way to perform routine operations.

For direct Docker administration, use the following commands from the installation directory.

```bash
cd /opt/mt-docker

# Inspect container status
docker compose ps

# Follow container logs
docker compose logs --tail 100 -f

# Monitor resource consumption
docker stats
```

### Common Maintenance Tasks

* Check the container status before troubleshooting.
* Review logs when a terminal or service fails to start.
* Monitor RAM and CPU consumption during trading activity.
* Create backups before rebuilding or updating the environment.
* Verify that terminal data remains available after container restarts.

> 💡 **Note:** Direct Docker commands may not perform the additional cleanup or validation implemented by the project's management script. Use the menu when available.

---

## 🛡️ Security Best Practices

MetaTrader Docker is designed to support a reduced-privilege container configuration and restricted remote desktop access.

Where configured, the deployment uses controls such as:

* 🛡️ **Reduced Capabilities:** Drop unnecessary Linux capabilities using `cap_drop: [ALL]`.
* 🔒 **Privilege Escalation Restrictions:** Apply `no-new-privileges: true`.
* 🌐 **Restricted Remote Access:** Bind the VNC/noVNC service to loopback rather than a public interface.
* 🔑 **Credential Protection:** Restrict access to `.env` and other sensitive configuration files.
* 📂 **Data Separation:** Keep persistent application data in host-mounted directories.

### Recommended Practices

1. Use SSH keys and disable password-based SSH authentication where practical.
2. Keep Ubuntu, Docker, and project dependencies updated.
3. Restrict inbound firewall rules to the ports you actually need.
4. Never commit `.env` files, passwords, API keys, or private download credentials.
5. Review container privileges and volume permissions before deploying to production.
6. Back up persistent data and test restoration procedures.
7. Avoid exposing remote desktop services directly to the public internet.

**Security considerations:** Container hardening reduces certain risks but does not eliminate them. Review the actual Docker Compose configuration, published ports, mounted directories, and host privileges before production use.

---

## 📜 License

This project is distributed under the **Apache License 2.0**.

See the [`LICENSE`](LICENSE) file for the complete license terms.

---

## ⚠️ Disclaimer

MetaTrader Docker is an independent open-source utility. It is **not affiliated with, endorsed by, or supported by MetaQuotes Ltd. or any brokerage firm**.

MetaTrader is a trademark of its respective owner. Users are responsible for complying with applicable software licenses and broker requirements.

### Financial Risk Warning

This software is provided **"AS IS"**, without warranties of any kind, to the extent permitted by applicable law.

Automated trading involves substantial financial risk and may result in the loss of capital. Running a trading terminal continuously does not guarantee uptime, successful order execution, profitability, or protection against market and connectivity risks.

Always test your Expert Advisors and trading strategies on a demo account before considering live deployment.

---

**Built for lightweight, manageable, and browser-accessible MetaTrader deployments on Linux VPS environments.**
****

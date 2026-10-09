# metatrader-docker

Trade 24/7 on a cheap Linux VPS. MT4 + MT5 in Docker, terminal-based, browser-accessible via noVNC. No Windows, no heavy GUI. 1 GB RAM friendly[cite: 1].

---

## 🚀 Key Features
- **All-in-One Automated Script:** A single shell script handles everything—from installing Docker, configuring swap memory, and setting up Wine dependencies, to generating all necessary container files (`Dockerfile`, `docker-compose.yml`, Supervisor configs) automatically.
- **Lightweight & RAM Friendly:** Fully optimized to run smoothly on low-resource VPS (ideal for 1 GB to 2 GB RAM servers)[cite: 1, 3].
- **Browser-Accessible (noVNC):** Access your MetaTrader graphical interface directly through your web browser without needing a heavy desktop environment[cite: 1, 3].
- **No Windows License Required:** Runs natively inside Linux/Docker containers, saving on Windows Server licensing costs[cite: 1, 3].
- **24/7 Reliability:** Perfect for running Expert Advisors (EAs) and automated trading strategies uninterrupted[cite: 1, 3].
- **Interactive Management Menu:** Includes built-in tools for installation, diagnostics, backups, updates, and service control[cite: 3].

---

## 📋 Prerequisites
Make sure your Linux VPS meets the following requirements:
- **OS:** Ubuntu 22.04 LTS (recommended) or compatible Linux distribution[cite: 3].
- **Privileges:** Root access (`sudo`)[cite: 3].
- **Resources:** At least 1 GB RAM and 10 GB free disk space[cite: 3].

---

## ⚙️ Quick Installation

You don't need to manually create configuration files or Dockerfiles. Everything is automated via the installation script.

1. Clone this repository on your VPS:
   ```bash
   git clone [https://github.com/Kurumim3/metatrader-docker.git](https://github.com/Kurumim3/metatrader-docker.git)
   cd metatrader-docker
Run the all-in-one interactive installer:

Bash
sudo bash install-mt-docker.sh
Follow the interactive menu on your screen to complete the base installation and install MT4 or MT5.

🖥️ Accessing the Interface
Once installed and running, you can access the secure web interface via noVNC using the generated VNC password and SSH port-forwarding instructions provided at the end of the script execution[cite: 3].

📄 License
This project is licensed under the Apache-2.0 License. See the LICENSE file for details.

#metatrader-docker

Trade 24/7 on a cheap Linux VPS. MT4 + MT5 in Docker, terminal-based, browser-accessible via noVNC. No Windows, no heavy GUI. 1 GB RAM friendly.

🚀 Features

Lightweight & RAM Friendly: Fully optimized to run smoothly on low-spec cloud servers (optimized for 1 GB–2 GB RAM VPS).

Browser-Accessible (noVNC): Access your MetaTrader graphical interface directly through your web browser without needing a heavy desktop environment.

No Windows License Required: Runs natively inside a secure Linux Docker container, avoiding costly Windows Server licenses.

24/7 Reliability: Perfect for running Expert Advisors (EAs), indicators, and automated trading strategies uninterrupted.

Interactive Management Script: Includes an all-in-one automation script to handle base setup, terminal installation, checks, backups, and container maintenance.

📋 Prerequisites

Make sure your Linux VPS has the following installed (the automated script can install Docker for you if needed):

Ubuntu 22.04 LTS (recommended) or compatible Linux distribution

Root privileges (sudo)

⚙️ Quick Installation

Clone the repository:

git clone https://github.com/Kurumim3/metatrader-docker.git
cd metatrader-docker


Run the interactive installer script:

sudo bash install-mt-docker.sh


Follow the interactive menu:

Choose Option 1 to set up the base environment (Docker, swap space, build the image, and start the container).

Choose Option 2 to automatically download and install MetaTrader 4 and/or MetaTrader 5.

🔒 Accessing noVNC

Once the container is running and the terminals are installed, you can access the graphical desktop via browser. By default, it binds locally to port 6080.

To connect securely from your local machine via an SSH tunnel:

ssh -N -p 22 -L 6080:127.0.0.1:6080 root@YOUR_VPS_IP


Then open your browser and navigate to:

http://localhost:6080/vnc.html?autoconnect=1&resize=scale


(Check your generated .env file for your automatically generated secure VNC password).

🛠️ Management & Maintenance

Run the script anytime to manage your setup:

sudo bash install-mt-docker.sh


Status / Diagnostics: Check container health and active processes.

Operations: Start, stop, or restart individual MT4/MT5 services.

Maintenance: Run manual backups, updates, or view live container logs.

📄 License

This project is open-source and licensed under the Apache-2.0 License. See the LICENSE file for more details.

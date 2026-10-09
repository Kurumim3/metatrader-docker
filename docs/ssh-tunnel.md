Markdown
# 🔒 Secure Access via SSH Tunnel

By default, the **noVNC** interface binds exclusively to `127.0.0.1:6080` on the remote VPS. This prevents unauthorized direct web access from the public internet.

---

## 🛠️ Step 1: Establish the SSH Tunnel

Run the following command on your local workstation (terminal, PowerShell, or command prompt), replacing `SSH_PORT` and `VPS_IP` with your actual server parameters:

```bash
ssh -N -p SSH_PORT -L 6080:127.0.0.1:6080 root@VPS_IP
Parameter Breakdown:
-N: Instructs SSH not to execute a remote shell command (port forwarding only).

-p SSH_PORT: Specifies your VPS SSH port (default is usually 22).

-L 6080:127.0.0.1:6080: Forwards traffic from localhost:6080 to the remote loopback address.

root@VPS_IP: Your server username and public IP address.

⚠️ Important: Keep this terminal window open while using the web interface. Closing it terminates the tunnel.

🌐 Step 2: Access MetaTrader in Your Browser
Once the tunnel is active, open your web browser and navigate to:

Plaintext
http://localhost:6080/vnc.html?autoconnect=1&resize=scale
Enter the VNC_PASSWORD generated during the base installation (stored in .env).

💡 Troubleshooting
Connection Refused: Ensure the SSH tunnel is active and the Docker container is running (docker compose ps).

Authentication Failure: Verify the password in /opt/mt-docker/.env under VNC_PASSWORD.

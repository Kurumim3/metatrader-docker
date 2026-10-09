# 🔒 Secure Access via SSH Tunnel

By default, the **noVNC** interface binds exclusively to `127.0.0.1:6080` on the remote VPS. This prevents unauthorized direct web access from the public internet.

---

## 🛠️ Step 1: Establish the SSH Tunnel

Run the following command on your local workstation (terminal, PowerShell, or command prompt), replacing `SSH_PORT` and `VPS_IP` with your actual server parameters:

```bash
ssh -N -p SSH_PORT -L 6080:127.0.0.1:6080 root@VPS_IP

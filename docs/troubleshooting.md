# 🔍 Troubleshooting & Common Issues

This guide provides practical solutions for the most frequent operational challenges encountered when running MetaTrader 4 and 5 in containerized Linux environments.

---

## 1. High Memory Consumption & OOM Crashes

### Symptoms
- MetaTrader exits abruptly without descriptive error entries in the application log.
- Container health check reports unhealthy or exits with code `137`.

### Root Cause
Wine environments running modern MetaTrader builds alongside GUI components require sufficient virtual memory headroom, particularly during initial chart history loading.

### Solution
1. Verify host swap configuration:
   ```bash
   free -m
Ensure at least 1 GB to 2 GB of swap space is active. If swap is absent, rerun the host preparation script:

Bash
sudo bash scripts/setup-host.sh
Reduce terminal memory footprints by limiting the maximum bars allowed per chart under:
Tools -> Options -> Charts -> Max bars in chart.

2. Display and Rendering Artifacts
Symptoms
Graphical elements or text fonts appear garbled or missing inside the browser GUI.

Solution
Ensure core Windows font equivalents are present in the Wine prefix. Run inside the container:

Bash
docker compose exec mt winetricks corefonts
Adjust display resolution in /opt/mt-docker/.env:

Bash
RESOLUTION=1024x600x16
Restart the services after updating:

Bash
docker compose up -d
3. Terminal Process Does Not Start Automatically
Symptoms
Web interface connects via noVNC, Fluxbox desktop loads, but MetaTrader does not launch.

Solution
Check the Supervisor service state:

Bash
docker compose exec mt mt-sv status
Verify installer logs for potential prefix initialization failures:

Bash
cat /opt/mt-docker/data/logs/setup-mt4.log
cat /opt/mt-docker/data/logs/setup-mt5.log
If necessary, trigger a forced reinstallation of the specific terminal target:

Bash
docker compose exec mt mt-install mt5 --force

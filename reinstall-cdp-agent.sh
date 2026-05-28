#!/bin/bash -x
set -e
read -p "This will remove the old CDP agent. Press Enter to continue or Ctrl+C to cancel..."

# Qbnox: Install the new driver
systemctl stop cdp-agent 2>/dev/null || true
cd /lib/modules/r1soft 2>/dev/null || true
wget https://beta.r1soft.com/modules/Ubuntu_2404_x64/hcpdriver-cki-6.8.0-117-generic.442.ko 2>/dev/null || true
unlink hcpdriver.o 2>/dev/null || true
ln -s /lib/modules/r1soft/hcpdriver-cki-6.8.0-117-generic.442.ko hcpdriver.o 2>/dev/null || true
#systemctl start cdp-agent

# Stop and remove old agent
systemctl stop cdp-agent 2>/dev/null || true
systemctl disable cdp-agent 2>/dev/null || true
apt-get remove --purge -y r1soft-cdp-enterprise-agent || true
apt-get autoremove -y
rm -rf /etc/cdp-agent /opt/cdp-agent /var/log/cdp-agent

# Install new agent
wget -qO - http://repo.r1soft.com/r1soft.asc | gpg --dearmor | tee /usr/share/keyrings/r1soft.gpg > /dev/null
echo "deb [signed-by=/usr/share/keyrings/r1soft.gpg] http://repo.r1soft.com/apt stable main" | tee /etc/apt/sources.list.d/r1soft.list
apt-get update -y
apt-get install -y r1soft-cdp-enterprise-agent

# Enable and start service
systemctl enable cdp-agent
systemctl start cdp-agent

# Verify
systemctl status cdp-agent --no-pager
ss -lntp | grep 1167 || echo "Port 1167 not listening yet"
echo "CDP Agent reinstall process completed."

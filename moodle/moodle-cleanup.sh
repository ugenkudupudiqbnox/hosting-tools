sudo systemctl stop mariadb
sudo systemctl stop crowdsec-firewall-bouncer
sudo systemctl disable crowdsec-firewall-bouncer
sudo rm /etc/systemd/system/crowdsec-firewall-bouncer.service
# Also check for any override directories
sudo rm -rf /etc/systemd/system/crowdsec-firewall-bouncer.service.d

sudo apt purge nginx mariadb-server mariadb-client mariadb-common -y
sudo apt purge mariadb-* -y
sudo apt purge -y crowdsec crowdsec-firewall-bouncer-nftables
sudo rm -rf /var/lib/mysql
sudo rm -rf /etc/mysql
sudo rm -rf /var/log/mysql
sudo rm -rf /etc/crowdsec
sudo rm -rf /var/lib/crowdsec
sudo rm -rf /var/log/crowdsec*
sudo rm -rf /var/www/moodle
sudo rm -rf /etc/nginx
sudo rm -rf /opt/*

sudo nft list tables
sudo nft delete table inet crowdsec
sudo systemctl restart nftables

sudo apt autoremove --purge -y
sudo apt autoclean
sudo systemctl daemon-reload
sudo systemctl reset-failed



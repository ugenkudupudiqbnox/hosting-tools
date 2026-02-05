# Moodle 5.1.1 Automated Installation Script

This script automates the complete installation of Moodle 5.1.1 with enterprise-grade security on Ubuntu 22.04 LTS.

## Features

✅ **Complete Stack Installation**
- MariaDB 11.4.10
- PHP 8.3-FPM with all required extensions
- Nginx web server
- Redis session caching
- Moodle 5.1.1 (latest stable)

✅ **3-Layer Security (Defense in Depth)**
- **Layer 1**: CrowdSec - Community threat intelligence
- **Layer 2**: ModSecurity 3 - Application firewall with 1,684 OWASP rules
- **Layer 3**: fail2ban - Behavioral monitoring with 5 jails

✅ **Production-Ready Features**
- SSL/TLS certificates (Let's Encrypt)
- 512MB file upload support
- Extended timeouts for large operations
- Automated daily database backups
- Weekly full system backups
- Redis session storage
- Performance optimizations

✅ **All Known Issues Fixed**
- Session persistence during course restore
- ModSecurity exclusions for Moodle AJAX
- Repository file picker compatibility
- Long query string handling

## Prerequisites

- **Operating System**: Ubuntu 22.04 LTS (fresh installation recommended)
- **Hardware**: Minimum 4 CPU cores, 8GB RAM, 50GB disk
- **Network**: Internet connection for package downloads
- **Domain**: Registered domain name pointing to server IP (for SSL)
- **Access**: Root or sudo privileges

## Quick Start

### 1. Download the Script

```bash
# If you don't have it yet, download from your source
cd /home/ubuntu/devops/moodle
chmod +x install-moodle.sh
```

### 2. Run the Installation

**For production with SSL:**
```bash
sudo ./install-moodle.sh learn.example.com
```

**For local testing (no SSL):**
```bash
sudo ./install-moodle.sh
# or
sudo ./install-moodle.sh localhost
```

### 3. During Installation

**No prompts required!** The script automatically:
- ✅ Detects CPU cores and RAM
- ✅ Generates secure passwords using OpenSSL
- ✅ Optimizes all configurations
- ✅ Creates credentials file with all passwords
- ✅ Displays credentials on screen at completion

### 4. Installation Time

- **Total time**: 15-20 minutes
- **ModSecurity compilation**: 10-15 minutes (longest step)
- The script will show progress for each step

### 5. Credentials Generated

**All passwords are auto-generated and saved!**

The script creates two copies of credentials:
- `/root/moodle-credentials.txt` (secure root location)
- `./moodle-credentials.txt` (current directory)

**Credentials file contains:**
- Database name, user, and password
- MariaDB root password
- Moodle URL and directories
- System resources detected
- Optimized configuration values
- All configuration file paths
- Next steps and useful commands

**Displayed on screen:**
At the end of installation, all credentials are displayed in a formatted box for easy copying.

**Security:**
- Files are created with `600` permissions (owner read/write only)
- Store credentials in a password manager
- Delete credentials files after saving elsewhere

### 6. After Installation

1. **Access Moodle web installer**:
   - Production: `https://learn.example.com`
   - Local: `http://localhost`

2. **Complete the web-based setup wizard**:
   - Database settings are pre-configured
   - Create your admin account
   - Configure site settings

3. **Verify installation**:
   ```bash
   # Check all services
   systemctl status nginx php8.3-fpm mariadb redis-server

   # Check security layers
   fail2ban-client status
   cscli decisions list
   tail -f /var/log/modsec_audit.log
   ```

## Script Usage

### Syntax
```bash
sudo ./install-moodle.sh [FQDN]
```

### Parameters
- `FQDN` (optional): Fully qualified domain name
  - Example: `learn.example.com`
  - If not provided, uses `localhost` (no SSL)

### Examples

**Production deployment:**
```bash
sudo ./install-moodle.sh learn.myschool.edu
```

**Development/testing:**
```bash
sudo ./install-moodle.sh localhost
```

**Default (localhost):**
```bash
sudo ./install-moodle.sh
```

## What Gets Installed

### System Packages
- MariaDB 11.4.10 (database server)
- PHP 8.3 and extensions
- Nginx (web server)
- Redis (session storage)
- Composer (dependency manager)
- Git, curl, wget, unzip
- Graphics tools (graphviz, ghostscript)
- Security tools (fail2ban, CrowdSec, ModSecurity)

### Moodle Configuration
- **Location**: `/var/www/moodle`
- **Data directory**: `/opt/www/moodledata`
- **Backup directory**: `/opt/backups/moodle`
- **Database**: `moodle` (user: `moodleuser`)

### Security Features
- **fail2ban**: 5 jails monitoring Moodle, Nginx, SSH
- **CrowdSec**: 6+ collections for threat detection
- **ModSecurity**: 1,684 OWASP rules with Moodle exclusions

### Automated Backups
- **Daily**: Database backup at 2:00 AM (7-day retention)
- **Weekly**: Full backup on Sunday at 3:00 AM (4-week retention)
- **Location**: `/opt/backups/moodle/`

## File Locations

```
/var/www/moodle/              # Moodle installation
  ├── public/                 # Web root
  ├── config.php              # Configuration
  └── vendor/                 # Composer dependencies

/opt/www/moodledata/          # Moodle data (not web-accessible)

/opt/backups/moodle/          # Backups
  ├── database/               # Daily DB backups
  └── full/                   # Weekly full backups

/etc/nginx/
  ├── sites-available/        # Virtual host configs
  └── modsec/                 # ModSecurity configuration

/var/log/
  ├── nginx/                  # Web server logs
  ├── php8.3-fpm.log         # PHP logs
  ├── mysql/                  # Database logs
  ├── modsec_audit.log       # ModSecurity logs
  ├── fail2ban.log           # fail2ban logs
  └── moodle-backup.log      # Backup logs
```

## Configuration Files

After installation, key configuration files:

- **Moodle**: `/var/www/moodle/config.php`
- **Nginx**: `/etc/nginx/sites-available/[your-domain]`
- **PHP**: `/etc/php/8.3/fpm/conf.d/99-moodle.ini`
- **MariaDB**: `/etc/mysql/mariadb.conf.d/99-moodle-optimized.cnf`
- **ModSecurity**: `/etc/nginx/modsec/main.conf`
- **fail2ban**: `/etc/fail2ban/jail.local`

## Post-Installation Tasks

### 1. Complete Web Setup
Access your Moodle URL and follow the installation wizard.

### 2. Configure Email (Optional)
Edit `/var/www/moodle/config.php` to add SMTP settings:
```php
$CFG->smtphosts = 'smtp.example.com:587';
$CFG->smtpuser = 'your-email@example.com';
$CFG->smtppass = 'your-password';
$CFG->smtpsecure = 'tls';
$CFG->noemailever = false;
```

### 3. Install Themes (Optional)
```bash
cd /var/www/moodle/public/theme
sudo -u www-data git clone https://github.com/willianmano/moodle-theme_moove.git moove
sudo -u www-data php /var/www/moodle/admin/cli/purge_caches.php
```

### 4. Set Up Cron
Add to system cron if not already configured:
```bash
sudo crontab -u www-data -e
# Add:
* * * * * /usr/bin/php /var/www/moodle/admin/cli/cron.php
```

## Monitoring & Maintenance

### Check Service Status
```bash
# All services
systemctl status nginx php8.3-fpm mariadb redis-server

# Security services
systemctl status fail2ban crowdsec
```

### Check Security Logs
```bash
# fail2ban status
sudo fail2ban-client status
sudo fail2ban-client status moodle-auth

# CrowdSec decisions
sudo cscli decisions list
sudo cscli metrics

# ModSecurity blocks
sudo tail -50 /var/log/modsec_audit.log
```

### Check Backups
```bash
# View backup log
tail -f /var/log/moodle-backup.log

# List backups
ls -lh /opt/backups/moodle/database/
ls -lh /opt/backups/moodle/full/
```

### Manual Backup
```bash
# Database only
sudo /usr/local/bin/moodle-db-backup.sh

# Full backup
sudo /usr/local/bin/moodle-full-backup.sh
```

## Troubleshooting

### Installation Fails

**Check logs**:
```bash
# Nginx errors
tail -50 /var/log/nginx/error.log

# PHP errors
tail -50 /var/log/php8.3-fpm.log

# MariaDB errors
tail -50 /var/log/mysql/error.log
```

**Common issues**:
1. **Port 80/443 already in use**: Stop conflicting services
2. **SSL certificate fails**: Ensure DNS points to server IP
3. **Out of memory**: Increase RAM or disable ModSecurity temporarily

### Can't Access Moodle

**Check Nginx**:
```bash
sudo nginx -t
sudo systemctl status nginx
```

**Check PHP-FPM**:
```bash
sudo systemctl status php8.3-fpm
```

**Check firewall**:
```bash
sudo ufw status
# If needed:
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
```

### ModSecurity Blocking Legitimate Requests

**Check audit log**:
```bash
sudo tail -100 /var/log/modsec_audit.log | grep "Access denied"
```

**Disable temporarily**:
```bash
# Edit virtual host
sudo nano /etc/nginx/sites-available/[your-domain]
# Comment out:
# modsecurity on;
# modsecurity_rules_file /etc/nginx/modsec/main.conf;

sudo systemctl reload nginx
```

### Session/Login Issues

**Purge caches**:
```bash
sudo -u www-data php /var/www/moodle/admin/cli/purge_caches.php
redis-cli FLUSHALL
sudo systemctl restart php8.3-fpm nginx
```

## Uninstallation

To remove Moodle and all components:

```bash
# Stop services
sudo systemctl stop nginx php8.3-fpm mariadb redis-server

# Remove packages
sudo apt remove --purge nginx php8.3* mariadb-server redis-server fail2ban crowdsec

# Remove files
sudo rm -rf /var/www/moodle
sudo rm -rf /opt/www/moodledata
sudo rm -rf /opt/backups/moodle
sudo rm -rf /etc/nginx/modsec
sudo rm /etc/nginx/sites-enabled/*
sudo rm /etc/nginx/sites-available/[your-domain]

# Remove database
sudo mysql -u root -p -e "DROP DATABASE moodle; DROP USER 'moodleuser'@'localhost';"
```

## Security Considerations

### Change Default Passwords
The script prompts for passwords during installation. **Never use default/weak passwords in production!**

### Firewall Configuration
```bash
# Enable UFW firewall
sudo ufw enable
sudo ufw allow ssh
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
```

### Regular Updates
```bash
# System updates
sudo apt update && sudo apt upgrade

# Moodle updates
cd /var/www/moodle
sudo -u www-data git pull
sudo -u www-data composer install --no-dev
sudo -u www-data php admin/cli/upgrade.php --non-interactive
```

### SSL Certificate Renewal
Let's Encrypt certificates auto-renew via certbot.timer:
```bash
# Check renewal status
sudo certbot renew --dry-run

# Manual renewal
sudo certbot renew
```

## Performance Tuning

The script optimizes for 4 CPU cores and 8-15GB RAM. For different specs:

**Edit PHP-FPM pool**: `/etc/php/8.3/fpm/pool.d/zzz-moodle-optimized.conf`
```ini
pm.max_children = [CPU_CORES * 10-20]
```

**Edit MariaDB**: `/etc/mysql/mariadb.conf.d/99-moodle-optimized.cnf`
```ini
innodb_buffer_pool_size = [50-70% of available RAM]
```

**Edit Redis**: `/etc/redis/redis.conf`
```ini
maxmemory [5-10% of available RAM]
```

## Support & Documentation

- **Full Documentation**: See `CLAUDE.md` for detailed configuration
- **Moodle Docs**: https://docs.moodle.org/
- **Security**: https://moodle.org/security/
- **ModSecurity CRS**: https://coreruleset.org/
- **CrowdSec**: https://docs.crowdsec.net/

## Script Information

- **Version**: 1.0
- **Generated**: 2026-02-05
- **Compatible**: Ubuntu 22.04 LTS
- **Moodle Version**: 5.1.1 (MOODLE_501_STABLE)
- **Lines of Code**: 948
- **Estimated Time**: 15-20 minutes

## License

This script is provided as-is for educational and production use. Based on official Moodle installation guidelines and security best practices.

---

**Generated from CLAUDE.md installation guide**
**Includes all fixes for known issues as of 2026-02-05**

# Managed Hosting Tools

Hosting automation and helper scripts for Moodle and Pressbooks deployments.

## Repository Layout

- `moodle/` contains Moodle-specific scripts.
  - `install-moodle-nginx.sh` is the Nginx-based Moodle 5.1.1 installer.
  - `install-moodle-apache.sh` is the Apache-based Moodle 5.1.1 installer.
  - `moodle-cleanup.sh` contains Moodle teardown/cleanup commands.
- `pb/` contains Pressbooks-specific scripts and helpers.
  - `install-pressbooks-bedrock-apache.sh` installs Pressbooks on Apache.
  - `pressbooks-blue-green-clone-vhost-apache.sh` handles blue/green clone-vhost operations.
  - `update-pressbooks.sh`, `setup-pressbooks-multisite.sh`, `flush-pressbooks-cache.sh`, `create-pressbooks-db.sh`, and `clean-pressbooks-db.sh` provide operational helpers.

## Moodle Nginx Installer

The primary Moodle installer automates a complete Moodle 5.1.1 deployment with enterprise-grade security on Ubuntu 22.04 LTS.

### Features

✅ **Complete Stack Installation**
- MariaDB 11.4.10
- PHP 8.3-FPM with all required extensions
- Nginx web server
- Redis session caching
- Moodle 5.1.1

✅ **3-Layer Security**
- **Layer 1**: CrowdSec
- **Layer 2**: ModSecurity 3 with OWASP CRS
- **Layer 3**: fail2ban

✅ **Production-Ready Defaults**
- Let's Encrypt SSL/TLS
- 512MB file upload support
- Extended timeouts for large operations
- Automated daily database backups
- Weekly full backups
- Redis-backed sessions
- Performance optimizations

✅ **Known Moodle Fixes Included**
- Session persistence during course restore
- ModSecurity exclusions for Moodle AJAX
- Repository file picker compatibility
- Long query string handling

### Prerequisites

- **Operating System**: Ubuntu 22.04 LTS
- **Hardware**: Minimum 4 CPU cores, 8GB RAM, 50GB disk
- **Network**: Internet access for package downloads
- **Domain**: Registered domain name pointing to the server IP for SSL installs
- **Access**: Root or sudo privileges

### Quick Start

```bash
cd /root/hosting-tools
chmod +x moodle/install-moodle-nginx.sh
sudo ./moodle/install-moodle-nginx.sh learn.example.com
```

For local testing without SSL:

```bash
sudo ./moodle/install-moodle-nginx.sh localhost
```

### Script Usage

```bash
sudo ./moodle/install-moodle-nginx.sh [FQDN]
```

- `FQDN` is optional.
- If omitted, the installer uses `localhost` and skips SSL setup.

### What the Installer Configures

#### System Packages
- MariaDB 11.4.10
- PHP 8.3 and required extensions
- Nginx
- Redis
- Composer
- fail2ban, CrowdSec, and ModSecurity

#### Moodle Paths

```text
/var/www/moodle/              # Moodle installation
  ├── public/                 # Web root
  ├── config.php              # Configuration
  └── vendor/                 # Composer dependencies

/opt/www/moodledata/          # Moodle data (not web-accessible)
/opt/backups/moodle/          # Backups
```

#### Important Configuration Files
- `/var/www/moodle/config.php`
- `/etc/nginx/sites-available/[your-domain]`
- `/etc/php/8.3/fpm/conf.d/99-moodle.ini`
- `/etc/mysql/mariadb.conf.d/99-moodle-optimized.cnf`
- `/etc/nginx/modsec/main.conf`
- `/etc/fail2ban/jail.local`

### After Installation

1. Access Moodle:
   - Production: `https://learn.example.com`
   - Local: `http://localhost`
2. Complete the Moodle web installer.
3. Verify services:

```bash
systemctl status nginx php8.3-fpm mariadb redis-server
fail2ban-client status
cscli decisions list
tail -f /var/log/modsec_audit.log
```

### Monitoring and Maintenance

Check backups:

```bash
tail -f /var/log/moodle-backup.log
ls -lh /opt/backups/moodle/database/
ls -lh /opt/backups/moodle/full/
```

Run backups manually:

```bash
sudo /usr/local/bin/moodle-db-backup.sh
sudo /usr/local/bin/moodle-full-backup.sh
```

Purge Moodle caches if needed:

```bash
sudo -u www-data php /var/www/moodle/admin/cli/purge_caches.php
redis-cli FLUSHALL
sudo systemctl restart php8.3-fpm nginx
```

### Troubleshooting

Check service and error logs:

```bash
sudo nginx -t
sudo systemctl status nginx
sudo systemctl status php8.3-fpm
tail -50 /var/log/nginx/error.log
tail -50 /var/log/php8.3-fpm.log
tail -50 /var/log/mysql/error.log
```

For ModSecurity false positives:

```bash
sudo tail -100 /var/log/modsec_audit.log | grep "Access denied"
```

### Security Notes

- Use strong production passwords.
- Enable and review UFW rules as appropriate for the host.
- Keep Ubuntu packages, Moodle, and supporting services patched.
- Test certificate renewal with:

```bash
sudo certbot renew --dry-run
```

### Compatibility

- **Ubuntu**: 22.04 LTS
- **Moodle**: 5.1.1
- **Git branch**: `MOODLE_501_STABLE`

## Additional References

- `CLAUDE.md` contains the longer deployment guide and operational notes.
- Moodle documentation: https://docs.moodle.org/
- Moodle security: https://moodle.org/security/
- OWASP CRS: https://coreruleset.org/
- CrowdSec: https://docs.crowdsec.net/

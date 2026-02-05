# Moodle 5.1.1 Installation Guide with Nginx, MariaDB, and 3-Layer WAF

This document provides complete instructions for installing and configuring Moodle 5.1.1 on Ubuntu 22.04 with a production-ready setup including performance optimizations and layered security.

## Table of Contents
- [System Requirements](#system-requirements)
- [Architecture Overview](#architecture-overview)
- [Installation Steps](#installation-steps)
  - [1. System Preparation](#1-system-preparation)
  - [2. MariaDB Installation](#2-mariadb-installation)
  - [3. PHP 8.3 Installation](#3-php-83-installation)
  - [4. Nginx Installation](#4-nginx-installation)
  - [5. Moodle Installation](#5-moodle-installation)
  - [6. SSL Certificate Setup](#6-ssl-certificate-setup)
  - [7. Redis Session Caching](#7-redis-session-caching)
  - [8. Performance Optimization](#8-performance-optimization)
  - [9. Automated Backups](#9-automated-backups)
  - [10. Theme Customization](#10-theme-customization)
  - [11. Security Layer Installation](#11-security-layer-installation)
- [Configuration Files](#configuration-files)
- [Troubleshooting](#troubleshooting)
- [Maintenance](#maintenance)

## System Requirements

- **OS**: Ubuntu 22.04 LTS
- **CPU**: 4 cores minimum (optimizations tuned for this)
- **RAM**: 15GB minimum (8GB for applications, rest for system/cache)
- **Disk**: 310GB minimum (SSD recommended)
- **Network**: Static IP with domain configured (e.g., learn.qbnox.com)
- **Ports**: 80, 443 open for web traffic

## Architecture Overview

### Software Stack
- **Web Server**: Nginx 1.18+
- **Application**: Moodle 5.1.1
- **PHP**: PHP 8.3-FPM
- **Database**: MariaDB 11.4.10
- **Caching**: Redis 7.0+
- **SSL**: Let's Encrypt (Certbot)

### Security Layers (Defense in Depth)
1. **Layer 1 - CrowdSec**: Community-driven threat intelligence and IP reputation
2. **Layer 2 - ModSecurity 3**: Application-level WAF with OWASP Core Rule Set
3. **Layer 3 - fail2ban**: Behavioral monitoring and automatic banning

### Directory Structure
```
/var/www/moodle/              # Moodle installation root
  ├── public/                 # Web-accessible root (Moodle 5.x structure)
  ├── vendor/                 # Composer dependencies
  └── config.php              # Main configuration
/opt/www/moodledata/          # Moodle data directory (not web-accessible)
/opt/backups/moodle/          # Backup storage
  ├── database/               # Daily database backups (7-day retention)
  └── full/                   # Weekly full backups (4-week retention)
```

## Installation Steps

### 1. System Preparation

Update the system and install essential packages:

```bash
# Update package lists
sudo apt update && sudo apt upgrade -y

# Install essential packages
sudo apt install -y software-properties-common curl wget git unzip graphviz aspell ghostscript clamav

# Create directories
sudo mkdir -p /opt/www
sudo chown -R www-data:www-data /opt/www
```

### 2. MariaDB Installation

Moodle 5.1 requires MariaDB 10.4+ or MySQL 8.4+. We use MariaDB 11.4.10:

```bash
# Install MariaDB 11.4
curl -LsS https://r.mariadb.com/downloads/mariadb_repo_setup | sudo bash -s -- --mariadb-server-version=11.4
sudo apt update
sudo apt install -y mariadb-server mariadb-client

# Secure MariaDB installation
sudo mysql_secure_installation
# Answer: Y for all questions
# Set root password when prompted

# Create Moodle database and user
sudo mysql -u root -p << EOF
CREATE DATABASE moodle DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER 'moodleuser'@'localhost' IDENTIFIED BY 'moodleP@ss123';
GRANT ALL PRIVILEGES ON moodle.* TO 'moodleuser'@'localhost';
FLUSH PRIVILEGES;
EXIT;
EOF

# Optimize MariaDB for 4 cores, 15GB RAM
sudo tee /etc/mysql/mariadb.conf.d/99-moodle-optimized.cnf > /dev/null << 'EOF'
[mysqld]
# InnoDB Settings
innodb_buffer_pool_size = 4G
innodb_buffer_pool_instances = 4
innodb_log_file_size = 512M
innodb_flush_log_at_trx_commit = 2
innodb_flush_method = O_DIRECT

# Connection Settings
max_connections = 300
max_allowed_packet = 256M

# Timeout Settings (for large file uploads)
wait_timeout = 28800
interactive_timeout = 28800
net_read_timeout = 1800
net_write_timeout = 1800

# Query Cache (disabled in MariaDB 10.6+, but safe to include)
query_cache_size = 0
query_cache_type = 0

# Table Cache
table_open_cache = 4000
table_definition_cache = 2000

# Thread Settings
thread_cache_size = 50
thread_stack = 256K

# Temp Table Settings
tmp_table_size = 256M
max_heap_table_size = 256M

# Logging
slow_query_log = 1
slow_query_log_file = /var/log/mysql/mysql-slow.log
long_query_time = 2
log_error = /var/log/mysql/error.log
EOF

# Restart MariaDB
sudo systemctl restart mariadb
sudo systemctl enable mariadb
```

### 3. PHP 8.3 Installation

Moodle 5.1 requires PHP 8.2+. Install PHP 8.3 from ondrej/php PPA:

```bash
# Add PHP PPA
sudo add-apt-repository -y ppa:ondrej/php
sudo apt update

# Install PHP 8.3 and required extensions
sudo apt install -y php8.3-fpm php8.3-cli php8.3-common \
    php8.3-mysql php8.3-xml php8.3-xmlrpc php8.3-curl \
    php8.3-gd php8.3-imagick php8.3-cli php8.3-dev \
    php8.3-imap php8.3-mbstring php8.3-opcache \
    php8.3-soap php8.3-zip php8.3-intl php8.3-redis

# Configure PHP for large uploads and extended timeouts
sudo tee /etc/php/8.3/fpm/conf.d/99-moodle.ini > /dev/null << 'EOF'
# File Upload Settings
upload_max_filesize = 512M
post_max_size = 512M
max_input_vars = 5000

# Execution Timeout Settings (30 minutes for large file uploads)
max_execution_time = 1800
max_input_time = 1800
default_socket_timeout = 1800

# Memory Settings
memory_limit = 256M

# Session Settings
session.save_handler = redis
session.save_path = "tcp://127.0.0.1:6379"
EOF

# Configure OPcache for performance
sudo tee /etc/php/8.3/fpm/conf.d/99-moodle-opcache.ini > /dev/null << 'EOF'
opcache.enable = 1
opcache.memory_consumption = 256
opcache.interned_strings_buffer = 16
opcache.max_accelerated_files = 10000
opcache.revalidate_freq = 60
opcache.save_comments = 1
opcache.enable_cli = 0
EOF

# Optimize PHP-FPM pool for 4 cores, 15GB RAM
sudo tee /etc/php/8.3/fpm/pool.d/zzz-moodle-optimized.conf > /dev/null << 'EOF'
[www]
pm = dynamic
pm.max_children = 70
pm.start_servers = 10
pm.min_spare_servers = 5
pm.max_spare_servers = 20
pm.max_requests = 500
pm.process_idle_timeout = 10s
request_terminate_timeout = 1800

# Per-pool PHP settings
php_admin_value[memory_limit] = 256M
php_admin_value[max_execution_time] = 300
php_admin_flag[display_errors] = off
php_admin_value[error_log] = /var/log/php8.3-fpm-moodle.log
EOF

# Restart PHP-FPM
sudo systemctl restart php8.3-fpm
sudo systemctl enable php8.3-fpm
```

### 4. Nginx Installation

Install and configure Nginx as the web server:

```bash
# Install Nginx
sudo apt install -y nginx

# Create extended timeout configuration for large file uploads
sudo tee /etc/nginx/conf.d/moodle-timeouts.conf > /dev/null << 'EOF'
# Extended timeouts for large file uploads (30 minutes)
client_body_timeout 1800s;
client_header_timeout 1800s;
fastcgi_connect_timeout 1800s;
fastcgi_send_timeout 1800s;
fastcgi_read_timeout 1800s;
proxy_connect_timeout 1800s;
proxy_send_timeout 1800s;
proxy_read_timeout 1800s;
send_timeout 1800s;
EOF

# Create performance optimization configuration
sudo tee /etc/nginx/conf.d/moodle-performance.conf > /dev/null << 'EOF'
# FastCGI cache settings
fastcgi_cache_path /var/cache/nginx/fastcgi levels=1:2 keys_zone=moodle:100m inactive=60m;
fastcgi_cache_key "$scheme$request_method$host$request_uri";
fastcgi_cache_use_stale error timeout invalid_header http_500;
fastcgi_ignore_headers Cache-Control Expires Set-Cookie;

# Buffer settings
fastcgi_buffers 16 16k;
fastcgi_buffer_size 32k;
client_body_buffer_size 256k;
EOF

# Create cache directory
sudo mkdir -p /var/cache/nginx/fastcgi
sudo chown -R www-data:www-data /var/cache/nginx

# Note: Virtual host configuration will be created after SSL setup
```

### 5. Moodle Installation

Download and install Moodle 5.1.1:

```bash
# Install Composer (required for Moodle 5.x)
cd /tmp
curl -sS https://getcomposer.org/installer -o composer-setup.php
sudo php composer-setup.php --install-dir=/usr/local/bin --filename=composer
rm composer-setup.php

# Download Moodle 5.1.1
cd /var/www
sudo git clone --branch MOODLE_501_STABLE --depth 1 https://github.com/moodle/moodle.git
cd moodle

# Install Composer dependencies
sudo -u www-data composer install --no-dev --classmap-authoritative

# Set ownership and permissions
sudo chown -R www-data:www-data /var/www/moodle
sudo chmod -R 755 /var/www/moodle

# Create Moodle data directory
sudo mkdir -p /opt/www/moodledata
sudo chown -R www-data:www-data /opt/www/moodledata
sudo chmod -R 770 /opt/www/moodledata

# Create initial config.php (will be updated after installation)
sudo -u www-data tee /var/www/moodle/config.php > /dev/null << 'EOF'
<?php
unset($CFG);
global $CFG;
$CFG = new stdClass();

$CFG->dbtype    = 'mariadb';
$CFG->dblibrary = 'native';
$CFG->dbhost    = 'localhost';
$CFG->dbname    = 'moodle';
$CFG->dbuser    = 'moodleuser';
$CFG->dbpass    = 'moodleP@ss123';
$CFG->prefix    = 'mdl_';
$CFG->dboptions = array(
    'dbpersist' => 0,
    'dbport' => '',
    'dbsocket' => '',
    'dbcollation' => 'utf8mb4_unicode_ci',
);

$CFG->wwwroot   = 'https://learn.qbnox.com';
$CFG->dataroot  = '/opt/www/moodledata';
$CFG->admin     = 'admin';

$CFG->directorypermissions = 0770;

require_once(__DIR__ . '/lib/setup.php');
EOF
```

### 6. SSL Certificate Setup

Install SSL certificate with Let's Encrypt:

```bash
# Install Certbot
sudo apt install -y certbot python3-certbot-nginx

# Obtain SSL certificate (replace with your domain)
sudo certbot certonly --nginx -d learn.qbnox.com --non-interactive --agree-tos -m admin@qbnox.com

# Create Nginx virtual host with SSL
sudo tee /etc/nginx/sites-available/learn.qbnox.com > /dev/null << 'EOF'
server {
    listen 80;
    server_name learn.qbnox.com;
    return 301 https://$server_name$request_uri;
}

server {
    listen 443 ssl http2;
    server_name learn.qbnox.com;

    root /var/www/moodle/public;
    index index.php index.html index.htm;

    # SSL Configuration
    ssl_certificate /etc/letsencrypt/live/learn.qbnox.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/learn.qbnox.com/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers on;

    # File upload size limit
    client_max_body_size 512M;

    # Logging
    access_log /var/log/nginx/moodle-access.log;
    error_log /var/log/nginx/moodle-error.log;

    # Moodle rewrite rules
    location / {
        try_files $uri $uri/ =404;
    }

    # PHP-FPM configuration
    location ~ [^/]\.php(/|$) {
        fastcgi_split_path_info ^(.+\.php)(/.+)$;
        fastcgi_pass unix:/run/php/php8.3-fpm.sock;
        fastcgi_index index.php;
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
        fastcgi_param PATH_INFO $fastcgi_path_info;

        # FastCGI cache (disabled for admin/login pages)
        set $skip_cache 0;
        if ($request_uri ~* "/(admin|login|course/view)") {
            set $skip_cache 1;
        }
        fastcgi_cache_bypass $skip_cache;
        fastcgi_no_cache $skip_cache;
        fastcgi_cache moodle;
        fastcgi_cache_valid 200 60m;
    }

    # Deny access to sensitive files
    location ~ (/\.ht|\.git|\.env|composer\.(json|lock)) {
        deny all;
        return 404;
    }

    # Static file caching
    location ~* \.(jpg|jpeg|png|gif|ico|css|js|svg|woff|woff2|ttf|eot)$ {
        expires 30d;
        add_header Cache-Control "public, immutable";
    }
}
EOF

# Enable site and restart Nginx
sudo ln -sf /etc/nginx/sites-available/learn.qbnox.com /etc/nginx/sites-enabled/
sudo rm -f /etc/nginx/sites-enabled/default
sudo nginx -t
sudo systemctl restart nginx
sudo systemctl enable nginx

# Auto-renewal setup
sudo systemctl enable certbot.timer
sudo systemctl start certbot.timer
```

### 7. Redis Session Caching

Install Redis for session storage and caching:

```bash
# Install Redis
sudo apt install -y redis-server

# Configure Redis
sudo tee /etc/redis/redis.conf > /dev/null << 'EOF'
bind 127.0.0.1
port 6379
protected-mode yes
tcp-backlog 511
timeout 0
tcp-keepalive 300
daemonize yes
supervised systemd
pidfile /var/run/redis/redis-server.pid
loglevel notice
logfile /var/log/redis/redis-server.log
databases 16
save 900 1
save 300 10
save 60 10000
stop-writes-on-bgsave-error yes
rdbcompression yes
rdbchecksum yes
dbfilename dump.rdb
dir /var/lib/redis
maxmemory 512mb
maxmemory-policy allkeys-lru
EOF

# Restart Redis
sudo systemctl restart redis-server
sudo systemctl enable redis-server

# Update Moodle config.php with Redis session handler
sudo -u www-data tee -a /var/www/moodle/config.php > /dev/null << 'EOF'

// Redis session handler
$CFG->session_handler_class = '\core\session\redis';
$CFG->session_redis_host = '127.0.0.1';
$CFG->session_redis_port = 6379;
$CFG->session_redis_database = 0;
$CFG->session_redis_prefix = 'moodle_sess_';
$CFG->session_redis_acquire_lock_timeout = 120;
$CFG->session_redis_lock_expire = 7200;

// Extended session timeout (8 hours)
$CFG->sessiontimeout = 28800;
EOF
```

### 8. Performance Optimization

Add performance settings to Moodle configuration:

```bash
sudo -u www-data tee -a /var/www/moodle/config.php > /dev/null << 'EOF'

// Performance Settings
$CFG->cachejs = true;
$CFG->yuicomboloading = true;
$CFG->maxbytes = 536870912; // 512MB upload limit

// Disable debugging in production
$CFG->debug = 0;
$CFG->debugdisplay = 0;
$CFG->perfdebug = 0;
$CFG->debugpageinfo = 0;

// Session persistence (prevents logout during course restore and long operations)
$CFG->sessioncookiepath = '/';
$CFG->sessioncookiedomain = '';
$CFG->sessiontimeoutcounter = true;

// Email settings (configure SMTP if needed)
$CFG->noemailever = false;
EOF
```

### 9. Automated Backups

Set up automated database and full system backups:

```bash
# Create backup directories
sudo mkdir -p /opt/backups/moodle/{database,full}
sudo chown -R www-data:www-data /opt/backups/moodle

# Create database backup script
sudo tee /usr/local/bin/moodle-db-backup.sh > /dev/null << 'EOF'
#!/bin/bash
# Moodle Database Backup Script

# Configuration
DB_NAME="moodle"
DB_USER="moodleuser"
DB_PASS="moodleP@ss123"
BACKUP_DIR="/opt/backups/moodle/database"
RETENTION_DAYS=7

# Create backup with timestamp
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="$BACKUP_DIR/moodle_db_$TIMESTAMP.sql.gz"

# Perform backup
mariadb-dump --user="$DB_USER" --password="$DB_PASS" \
    --single-transaction --quick --lock-tables=false \
    --routines --triggers "$DB_NAME" | gzip > "$BACKUP_FILE"

# Check if backup was successful
if [ $? -eq 0 ]; then
    echo "$(date): Database backup successful - $BACKUP_FILE" >> /var/log/moodle-backup.log

    # Remove old backups
    find "$BACKUP_DIR" -name "moodle_db_*.sql.gz" -mtime +$RETENTION_DAYS -delete
else
    echo "$(date): Database backup FAILED" >> /var/log/moodle-backup.log
    exit 1
fi
EOF

# Create full system backup script
sudo tee /usr/local/bin/moodle-full-backup.sh > /dev/null << 'EOF'
#!/bin/bash
# Moodle Full Backup Script (Database + Files)

# Configuration
BACKUP_DIR="/opt/backups/moodle/full"
MOODLE_ROOT="/var/www/moodle"
MOODLE_DATA="/opt/www/moodledata"
RETENTION_WEEKS=4

# Create backup with timestamp
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_NAME="moodle_full_$TIMESTAMP"
BACKUP_PATH="$BACKUP_DIR/$BACKUP_NAME"

# Create temporary directory
mkdir -p "$BACKUP_PATH"

# Backup database
echo "$(date): Starting database backup..." >> /var/log/moodle-backup.log
/usr/local/bin/moodle-db-backup.sh
cp /opt/backups/moodle/database/moodle_db_*.sql.gz "$BACKUP_PATH/" 2>/dev/null | head -1

# Backup Moodle code
echo "$(date): Backing up Moodle code..." >> /var/log/moodle-backup.log
tar -czf "$BACKUP_PATH/moodle_code.tar.gz" -C /var/www moodle

# Backup Moodle data
echo "$(date): Backing up Moodle data..." >> /var/log/moodle-backup.log
tar -czf "$BACKUP_PATH/moodle_data.tar.gz" -C /opt/www moodledata

# Create archive
cd "$BACKUP_DIR"
tar -czf "$BACKUP_NAME.tar.gz" "$BACKUP_NAME"
rm -rf "$BACKUP_PATH"

if [ $? -eq 0 ]; then
    echo "$(date): Full backup successful - $BACKUP_NAME.tar.gz" >> /var/log/moodle-backup.log

    # Remove old backups (older than retention period)
    find "$BACKUP_DIR" -name "moodle_full_*.tar.gz" -mtime +$((RETENTION_WEEKS * 7)) -delete
else
    echo "$(date): Full backup FAILED" >> /var/log/moodle-backup.log
    exit 1
fi
EOF

# Make scripts executable
sudo chmod +x /usr/local/bin/moodle-db-backup.sh
sudo chmod +x /usr/local/bin/moodle-full-backup.sh

# Schedule automated backups with cron
sudo tee /etc/cron.d/moodle-backup > /dev/null << 'EOF'
# Moodle Automated Backups
# Daily database backup at 2:00 AM
0 2 * * * root /usr/local/bin/moodle-db-backup.sh

# Weekly full backup on Sunday at 3:00 AM
0 3 * * 0 root /usr/local/bin/moodle-full-backup.sh
EOF

# Create log file
sudo touch /var/log/moodle-backup.log
sudo chown www-data:www-data /var/log/moodle-backup.log
```

### 10. Theme Customization

Install and customize the Moove theme:

```bash
# Download Moove theme
cd /var/www/moodle/public/theme
sudo -u www-data git clone https://github.com/willianmano/moodle-theme_moove.git moove

# Customize theme footer branding
sudo sed -i "s/\$string\['themedevelopedby'\] = 'Developed by'/\$string['themedevelopedby'] = 'Maintained by'/g" \
    /var/www/moodle/public/theme/moove/lang/en/theme_moove.php

# Update footer template
sudo sed -i 's|https://moodle.com/|https://www.qbnoxsystems.com|g' \
    /var/www/moodle/public/theme/moove/templates/footer.mustache
sudo sed -i 's|Moodle|Qbnox Systems|g' \
    /var/www/moodle/public/theme/moove/templates/footer.mustache

# Clear Moodle cache
sudo -u www-data php /var/www/moodle/admin/cli/purge_caches.php
```

### 11. Security Layer Installation

Install the 3-layer defense-in-depth security stack:

#### Layer 3: fail2ban

```bash
# Install fail2ban
sudo apt install -y fail2ban

# Create Moodle-specific jail configuration
sudo tee /etc/fail2ban/jail.local > /dev/null << 'EOF'
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 5
destemail = admin@qbnox.com
sendername = Fail2Ban
action = %(action_mwl)s

[sshd]
enabled = true
port = ssh
logpath = /var/log/auth.log

[nginx-http-auth]
enabled = true
filter = nginx-http-auth
logpath = /var/log/nginx/moodle-error.log
maxretry = 3

[nginx-limit-req]
enabled = true
filter = nginx-limit-req
logpath = /var/log/nginx/moodle-error.log
maxretry = 10

[php-url-fopen]
enabled = true
filter = php-url-fopen
logpath = /var/log/nginx/moodle-access.log
maxretry = 3

[moodle-auth]
enabled = true
filter = moodle-auth
logpath = /var/log/nginx/moodle-access.log
maxretry = 5
bantime = 3600
EOF

# Create Moodle authentication failure filter
sudo tee /etc/fail2ban/filter.d/moodle-auth.conf > /dev/null << 'EOF'
[Definition]
failregex = ^<HOST> .* "POST /login/index\.php.*" (401|403|200)
            ^<HOST> .* "POST /login/index\.php.*" 200 .* "Invalid login"
ignoreregex =
EOF

# Restart fail2ban
sudo systemctl restart fail2ban
sudo systemctl enable fail2ban
```

#### Layer 1: CrowdSec

```bash
# Install CrowdSec
curl -s https://install.crowdsec.net | sudo sh

# Install firewall bouncer
sudo apt install -y crowdsec-firewall-bouncer-nftables

# Set up automatic detection
sudo cscli setup detect
sudo cscli setup install-hub

# Install additional security collections
sudo cscli collections install crowdsecurity/nginx
sudo cscli collections install crowdsecurity/linux
sudo cscli collections install crowdsecurity/sshd
sudo cscli collections install crowdsecurity/mariadb
sudo cscli collections install crowdsecurity/http-cve
sudo cscli collections install crowdsecurity/whitelist-good-actors

# Enable and start CrowdSec
sudo systemctl restart crowdsec
sudo systemctl enable crowdsec
sudo systemctl restart crowdsec-firewall-bouncer
sudo systemctl enable crowdsec-firewall-bouncer
```

#### Layer 2: ModSecurity 3 with OWASP CRS

```bash
# Install dependencies
sudo apt install -y libtool autoconf automake libxml2-dev libpcre2-dev \
    libyajl-dev libcurl4-openssl-dev libgeoip-dev liblmdb-dev \
    pkg-config libssl-dev zlib1g-dev git

# Clone and compile ModSecurity
cd /opt
sudo git clone --depth 1 https://github.com/owasp-modsecurity/ModSecurity.git
cd ModSecurity
sudo git submodule init
sudo git submodule update
sudo sh build.sh
sudo ./configure
sudo make -j$(nproc)
sudo make install

# Clone ModSecurity Nginx connector
cd /opt
sudo git clone --depth 1 https://github.com/owasp-modsecurity/ModSecurity-nginx.git

# Get Nginx version
NGINX_VERSION=$(nginx -v 2>&1 | grep -oP '\d+\.\d+\.\d+')

# Download matching Nginx source
cd /opt
sudo wget http://nginx.org/download/nginx-${NGINX_VERSION}.tar.gz
sudo tar -xzf nginx-${NGINX_VERSION}.tar.gz

# Compile Nginx with ModSecurity module
cd /opt/nginx-${NGINX_VERSION}
sudo ./configure --with-compat --add-dynamic-module=/opt/ModSecurity-nginx
sudo make modules
sudo cp objs/ngx_http_modsecurity_module.so /usr/share/nginx/modules/

# Download OWASP Core Rule Set
cd /opt
sudo git clone --depth 1 https://github.com/coreruleset/coreruleset.git /etc/nginx/modsec/owasp-crs
cd /etc/nginx/modsec/owasp-crs
sudo cp crs-setup.conf.example crs-setup.conf

# Configure ModSecurity
sudo mkdir -p /etc/nginx/modsec
sudo cp /opt/ModSecurity/modsecurity.conf-recommended /etc/nginx/modsec/modsecurity.conf
sudo cp /opt/ModSecurity/unicode.mapping /etc/nginx/modsec/

# Enable ModSecurity (detection mode initially)
sudo sed -i 's/SecRuleEngine DetectionOnly/SecRuleEngine On/g' /etc/nginx/modsec/modsecurity.conf

# Create ModSecurity main config
sudo tee /etc/nginx/modsec/main.conf > /dev/null << 'EOF'
Include /etc/nginx/modsec/modsecurity.conf
Include /etc/nginx/modsec/owasp-crs/crs-setup.conf
Include /etc/nginx/modsec/owasp-crs/rules/*.conf

# Moodle-specific exclusions to prevent false positives
# Rule 920350: Host header is a numeric IP address
SecRuleRemoveById 920350

# Rule 942450: SQL Hex Encoding Identified
SecRuleRemoveById 942450

# Disable some rules for Moodle admin area
SecRule REQUEST_URI "@beginsWith /admin" \
    "id:1000,phase:1,t:none,nolog,pass,ctl:ruleRemoveById=942100"

# Moodle AJAX Service Exclusions (prevents 403 errors on AJAX requests)
# Disable protocol enforcement for AJAX endpoints with long query strings
SecRule REQUEST_URI "@beginsWith /lib/ajax/service" \
    "id:1002,phase:1,t:none,nolog,pass,ctl:ruleRemoveById=920100,ctl:ruleRemoveById=920440"

# Increase PCRE limits for Moodle AJAX (handles long JSON-encoded parameters)
SecPcreMatchLimit 150000
SecPcreMatchLimitRecursion 150000

# Allow larger request bodies for Moodle (512MB for file uploads)
SecRequestBodyLimit 536870912
SecRequestBodyNoFilesLimit 262144

# Repository AJAX exclusions (file picker operations)
# Disable RCE detection for repository_ajax.php (false positives on 'env' parameter)
SecRule REQUEST_URI "@beginsWith /repository/repository_ajax.php" \
    "id:1003,phase:1,t:none,nolog,pass,ctl:ruleRemoveById=932340"
EOF

# Load ModSecurity module in Nginx (only for Moodle virtual host)
sudo sed -i '1i load_module modules/ngx_http_modsecurity_module.so;' /etc/nginx/nginx.conf

# Update Moodle virtual host to use ModSecurity
sudo sed -i '/server_name learn.qbnox.com;/a \    modsecurity on;\n    modsecurity_rules_file /etc/nginx/modsec/main.conf;' \
    /etc/nginx/sites-available/learn.qbnox.com

# Test and restart Nginx
sudo nginx -t
sudo systemctl restart nginx
```

## Configuration Files

### Moodle config.php (Complete)

```php
<?php
unset($CFG);
global $CFG;
$CFG = new stdClass();

// Database Configuration
$CFG->dbtype    = 'mariadb';
$CFG->dblibrary = 'native';
$CFG->dbhost    = 'localhost';
$CFG->dbname    = 'moodle';
$CFG->dbuser    = 'moodleuser';
$CFG->dbpass    = 'moodleP@ss123';
$CFG->prefix    = 'mdl_';
$CFG->dboptions = array(
    'dbpersist' => 0,
    'dbport' => '',
    'dbsocket' => '',
    'dbcollation' => 'utf8mb4_unicode_ci',
);

// Site Configuration
$CFG->wwwroot   = 'https://learn.qbnox.com';
$CFG->dataroot  = '/opt/www/moodledata';
$CFG->admin     = 'admin';
$CFG->directorypermissions = 0770;

// Redis Session Handler
$CFG->session_handler_class = '\core\session\redis';
$CFG->session_redis_host = '127.0.0.1';
$CFG->session_redis_port = 6379;
$CFG->session_redis_database = 0;
$CFG->session_redis_prefix = 'moodle_sess_';
$CFG->session_redis_acquire_lock_timeout = 120;
$CFG->session_redis_lock_expire = 7200;

// Session Settings
$CFG->sessiontimeout = 28800; // 8 hours

// Session Persistence (prevents logout during course restore and long operations)
$CFG->sessioncookiepath = '/';
$CFG->sessioncookiedomain = '';
$CFG->sessiontimeoutcounter = true;

// Performance Settings
$CFG->cachejs = true;
$CFG->yuicomboloading = true;
$CFG->maxbytes = 536870912; // 512MB

// Debug Settings (Disable in Production)
$CFG->debug = 0;
$CFG->debugdisplay = 0;
$CFG->perfdebug = 0;
$CFG->debugpageinfo = 0;

// Email Settings
$CFG->noemailever = false;

require_once(__DIR__ . '/lib/setup.php');
```

## Troubleshooting

### Common Issues

#### 1. HTTP 500 Error After Installation

**Cause**: Moodle 5.x uses `/public` subdirectory structure

**Solution**: Ensure Nginx root points to `/var/www/moodle/public`, not `/var/www/moodle`

#### 2. "PHP version too old" Error

**Cause**: Ubuntu 22.04 ships with PHP 8.1, Moodle 5.1 requires 8.2+

**Solution**: Install PHP 8.3 from ondrej/php PPA (see installation steps)

#### 3. "Composer dependencies not found" Error

**Cause**: Moodle 5.x requires Composer autoloader

**Solution**: Run `composer install --no-dev --classmap-authoritative` in `/var/www/moodle`

#### 4. Database Version Error

**Cause**: Moodle 5.1 requires MariaDB 10.4+ or MySQL 8.4+

**Solution**: Install MariaDB 11.4 from official repository (see installation steps)

#### 5. "Wrong dbtype" Error

**Cause**: Using 'mysqli' driver with MariaDB

**Solution**: Set `$CFG->dbtype = 'mariadb';` in config.php

#### 6. File Upload Timeouts (200MB+ files)

**Cause**: Default timeouts are too short for large file uploads

**Solution**: Increase all timeouts to 1800s (30 min):
- PHP: `max_execution_time`, `max_input_time`, `default_socket_timeout`
- PHP-FPM: `request_terminate_timeout`
- Nginx: all timeout directives
- MariaDB: `wait_timeout`, `net_read_timeout`, `net_write_timeout`
- Moodle: `sessiontimeout`

#### 7. ModSecurity Blocking Legitimate Requests

**Cause**: False positives from OWASP CRS rules

**Solution**: Add exclusions to `/etc/nginx/modsec/main.conf`:
```
SecRuleRemoveById [RULE_ID]
```

Check ModSecurity audit logs: `/var/log/modsec_audit.log`

#### 8. AJAX Requests Returning 403 Forbidden (service-nologin.php)

**Symptoms**:
- Browser console shows: `GET https://learn.qbnox.com/lib/ajax/service-nologin.php 403 (Forbidden)`
- Moodle dynamic features not working (templates, strings loading)

**Cause**: ModSecurity blocking AJAX requests with long query strings containing JSON-encoded parameters. Rule 920100 (Invalid HTTP Request Line) and PCRE match limits are exceeded.

**Solution**: The configuration in this guide already includes the fix. If you encounter this issue:

1. Check ModSecurity audit log:
```bash
sudo tail -50 /var/log/modsec_audit.log | grep -B 5 "service-nologin"
```

2. Verify AJAX exclusions are present in `/etc/nginx/modsec/main.conf`:
```apache
# Moodle AJAX Service Exclusions
SecRule REQUEST_URI "@beginsWith /lib/ajax/service" \
    "id:1002,phase:1,t:none,nolog,pass,ctl:ruleRemoveById=920100,ctl:ruleRemoveById=920440"

# Increase PCRE limits
SecPcreMatchLimit 150000
SecPcreMatchLimitRecursion 150000
```

3. Reload Nginx:
```bash
sudo nginx -t && sudo systemctl reload nginx
```

4. Test AJAX endpoint:
```bash
curl -I "https://learn.qbnox.com/lib/ajax/service-nologin.php?info=test"
# Should return HTTP 200
```

#### 9. Redis Session Handler Class Not Found After Cache Purge

**Symptoms**:
- Error: `Exception - Class "\core\session\redis" not found`
- 500 errors on styles.php, javascript.php, image.php

**Cause**: Namespace separator escape sequence issue in config.php. When using double quotes, `\r` in `\core\session\redis` is interpreted as carriage return.

**Solution**: Use **single quotes** for the session handler class in `/var/www/moodle/config.php`:

```php
// CORRECT - Use single quotes
$CFG->session_handler_class = '\core\session\redis';

// WRONG - Double quotes will cause issues
$CFG->session_handler_class = "\core\session\redis";
```

After fixing, restart PHP-FPM:
```bash
sudo systemctl restart php8.3-fpm
```

#### 10. Session Lost During Course Restore (requireloginerror)

**Symptoms**:
- First course restore works fine
- Second course restore fails with "requireloginerror"
- Error: "Course or activity not accessible. You are not logged in"
- Occurs during `repository_ajax.php` file upload operations

**Cause**: Session expires or is lost during long-running restore operations.

**Solution**: Add session persistence settings to `/var/www/moodle/config.php` (before `require_once` line):

```php
// Session persistence (prevents logout during course restore and long operations)
$CFG->sessioncookiepath = '/';
$CFG->sessioncookiedomain = '';
$CFG->sessiontimeoutcounter = true;
```

Then restart PHP-FPM:
```bash
sudo systemctl restart php8.3-fpm
```

**What these settings do**:
- `sessioncookiepath`: Ensures cookies work across all site paths
- `sessioncookiedomain`: Prevents domain-specific cookie issues
- `sessiontimeoutcounter`: Keeps session alive during admin operations

#### 11. JSON Parse Error in File Picker (Unexpected token '<')

**Symptoms**:
- Browser console: `SyntaxError: Unexpected token '<', "<html><h"... is not valid JSON`
- Error in `repository/filepicker.js` at `JSON.parse()`
- File picker not working during course restore

**Cause**: ModSecurity blocking `/repository/repository_ajax.php` with Rule 932340 (RCE detection). The legitimate `env` parameter is flagged as a security threat, causing the endpoint to return a 403 HTML error page instead of JSON.

**Solution**: The configuration in this guide already includes the fix. If you encounter this issue:

1. Check ModSecurity audit log:
```bash
sudo tail -50 /var/log/modsec_audit.log | grep -B 3 "repository_ajax"
```

2. Verify the exclusion is present in `/etc/nginx/modsec/main.conf`:
```apache
# Repository AJAX exclusions (file picker operations)
# Disable RCE detection for repository_ajax.php (false positives on 'env' parameter)
SecRule REQUEST_URI "@beginsWith /repository/repository_ajax.php" \
    "id:1003,phase:1,t:none,nolog,pass,ctl:ruleRemoveById=932340"
```

3. Reload Nginx:
```bash
sudo nginx -t && sudo systemctl reload nginx
```

4. Test the endpoint:
```bash
curl -I "https://learn.qbnox.com/repository/repository_ajax.php?action=list"
# Should return: HTTP 200 and Content-Type: application/json
```

### Log Locations

- **Nginx Access**: `/var/log/nginx/moodle-access.log`
- **Nginx Error**: `/var/log/nginx/moodle-error.log`
- **PHP-FPM**: `/var/log/php8.3-fpm-moodle.log`
- **MariaDB Error**: `/var/log/mysql/error.log`
- **MariaDB Slow Query**: `/var/log/mysql/mysql-slow.log`
- **Moodle**: `/opt/www/moodledata/` (various log files)
- **Backup**: `/var/log/moodle-backup.log`
- **fail2ban**: `/var/log/fail2ban.log`
- **CrowdSec**: `journalctl -u crowdsec`
- **ModSecurity**: `/var/log/modsec_audit.log`

### Useful Commands

```bash
# Check service status
sudo systemctl status nginx
sudo systemctl status php8.3-fpm
sudo systemctl status mariadb
sudo systemctl status redis-server
sudo systemctl status fail2ban
sudo systemctl status crowdsec

# Moodle cache management
sudo -u www-data php /var/www/moodle/admin/cli/purge_caches.php

# Check PHP-FPM pool status
sudo systemctl status php8.3-fpm
ps aux | grep php-fpm

# Check database connections
sudo mysql -u root -p -e "SHOW PROCESSLIST;"

# Test Nginx configuration
sudo nginx -t

# Reload Nginx without downtime
sudo nginx -s reload

# Check fail2ban status
sudo fail2ban-client status
sudo fail2ban-client status moodle-auth

# Check CrowdSec decisions
sudo cscli decisions list

# Check ModSecurity logs
sudo tail -f /var/log/modsec_audit.log
```

## Maintenance

### Regular Tasks

#### Daily
- Monitor backup logs: `tail -f /var/log/moodle-backup.log`
- Check disk space: `df -h`
- Review security alerts from CrowdSec and fail2ban

#### Weekly
- Review slow query logs
- Check for Moodle updates: https://moodle.org/downloads/
- Update CrowdSec hub: `sudo cscli hub update && sudo cscli hub upgrade`

#### Monthly
- Review and analyze access logs
- Update OWASP CRS: `cd /etc/nginx/modsec/owasp-crs && sudo git pull`
- Test backup restoration procedure
- Update system packages: `sudo apt update && sudo apt upgrade`

### Performance Monitoring

```bash
# Check PHP-FPM pool performance
sudo grep "pool www" /var/log/php8.3-fpm.log

# Monitor database performance
sudo mysql -u root -p -e "SHOW STATUS LIKE '%Threads%'; SHOW STATUS LIKE '%Questions%';"

# Check Redis memory usage
redis-cli INFO memory

# Monitor Nginx connections
sudo ss -tulpn | grep nginx
```

### Security Monitoring

```bash
# Review banned IPs
sudo fail2ban-client status moodle-auth

# Check CrowdSec alerts
sudo cscli alerts list

# Review ModSecurity blocks
sudo grep "ModSecurity: Access denied" /var/log/nginx/moodle-error.log
```

## Additional Resources

- **Moodle Documentation**: https://docs.moodle.org/
- **Moodle Security**: https://moodle.org/security/
- **OWASP ModSecurity CRS**: https://coreruleset.org/
- **CrowdSec Documentation**: https://docs.crowdsec.net/
- **fail2ban Manual**: https://www.fail2ban.org/

## Version Information

This guide was created for:
- Ubuntu 22.04 LTS
- Moodle 5.1.1
- PHP 8.3
- MariaDB 11.4.10
- Nginx 1.18+
- ModSecurity 3.0.14
- OWASP CRS 4.0
- CrowdSec Latest
- fail2ban Latest

## Important Notes

1. **Change Default Passwords**: Replace all default passwords (database, Moodle admin) with strong passwords
2. **Firewall Configuration**: Ensure firewall allows ports 80, 443, and SSH
3. **Backup Testing**: Regularly test backup restoration procedures
4. **Security Updates**: Keep all components updated with security patches
5. **ModSecurity Tuning**: Monitor false positives and adjust rules as needed
6. **Performance Monitoring**: Use tools like `htop`, `iotop`, `mytop` to monitor system resources
7. **SSL Renewal**: Certbot auto-renews, but verify with `sudo certbot renew --dry-run`
8. **Data Protection**: Ensure `/opt/www/moodledata` is NOT web-accessible
9. **Session Security**: Configure `$CFG->cookiesecure = true;` for HTTPS-only cookies
10. **Email Configuration**: Configure proper SMTP settings for production use

---

**Created**: 2026-02-05
**For**: Qbnox Systems
**Domain**: learn.qbnox.com
**Purpose**: Production Moodle LMS deployment with enterprise-grade security

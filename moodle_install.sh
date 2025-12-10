#!/usr/bin/env bash
#
# install_full_moodle_with_moove_and_cleanup.sh
# Full idempotent Moodle installer for Ubuntu 24.04 LTS with auto-sizing, Moove theme install,
# and optional git metadata cleanup (idempotent).
# Edit variables in the top section before running. Run as root.
set -euo pipefail
[ "${TRACE:-0}" -eq 1 ] && set -x

# -----------------------
# User-editable variables
# -----------------------
MOODLE_DIR="${MOODLE_DIR:-/var/www/moodle}"
MOODLE_PUBLIC_DIR="${MOODLE_PUBLIC_DIR:-${MOODLE_DIR}/public}"
MOODLEDATA="${MOODLEDATA:-/var/moodledata}"
WWW_USER="${WWW_USER:-www-data}"
WWW_GROUP="${WWW_GROUP:-www-data}"
MOODLE_WWWROOT="${MOODLE_WWWROOT:-http://localhost}"   # change to https://moodle.example.com
MOODLE_DB="${MOODLE_DB:-moodle}"
MOODLE_DB_USER="${MOODLE_DB_USER:-moodleuser}"
DB_PASS_FILE="${DB_PASS_FILE:-/root/.moodle_db_pass}"
ADMIN_PASS_FILE="${ADMIN_PASS_FILE:-/root/.moodle_admin_pass}"
MOODLE_FULLNAME="${MOODLE_FULLNAME:-Moodle site}"
MOODLE_SHORTNAME="${MOODLE_SHORTNAME:-Moodle}"
MOODLE_ADMINUSER="${MOODLE_ADMINUSER:-admin}"
MOODLE_ADMINEMAIL="${MOODLE_ADMINEMAIL:-admin@example.com}"
PHP_VERSION="${PHP_VERSION:-8.3}"   # follow Moodle docs
APACHE_VHOST="/etc/apache2/sites-available/moodle.conf"
MARIADB_TUNE_MARKER="/etc/mysql/mariadb.conf.d/99-moodle-mariadb.cnf"
MYSQLTUNER_BIN="/usr/local/bin/mysqltuner.pl"
BACKUP_BASE="/root/moodle_backups"
MYSQL_EXEC_CMD="${MYSQL_EXEC_CMD:-mysql -u root}"  # adjust if your root mysql needs password

# Upload configuration (change if needed)
UPLOAD_MAX_MB=${UPLOAD_MAX_MB:-512}

# Moove theme settings
INSTALL_MOOVE="${INSTALL_MOOVE:-yes}"               # set to "no" to skip automatic moove installation
MOODLE_BRANCH="${MOODLE_BRANCH:-MOODLE_401_STABLE}" # choose the branch/tag matching your Moodle version
MOOVE_REPO="${MOOVE_REPO:-https://github.com/willianmano/moodle-theme_moove.git}"

# Safety flags for shared systems (if needed)
TUNE_GLOBAL_APACHE="${TUNE_GLOBAL_APACHE:-yes}"
TUNE_GLOBAL_PHP="${TUNE_GLOBAL_PHP:-yes}"
TUNE_SYSCTL="${TUNE_SYSCTL:-yes}"
RUN_MYSQLTUNER="${RUN_MYSQLTUNER:-yes}"
INSTALL_PHP_VERSION="${INSTALL_PHP_VERSION:-yes}"

# CLEANUP OPTIONS (git metadata cleanup)
CLEANUP_GIT="${CLEANUP_GIT:-yes}"          # yes|no - remove .git metadata and repo cruft after install
CLEANUP_BACKUP="${CLEANUP_BACKUP:-yes}"    # yes|no - create tar.gz backup before cleaning
CLEANUP_BACKUP_DIR="${CLEANUP_BACKUP_DIR:-/root/moodle_backups/code_backup}"
CLEANUP_LOG="${CLEANUP_LOG:-/var/log/moodle_git_cleanup.log}"
# -----------------------

# -----------------------
# Derived system resources
# -----------------------
TOTAL_MEM_KB=$(awk '/MemTotal/{print $2}' /proc/meminfo || echo 0)
TOTAL_MEM_MB=$(( TOTAL_MEM_KB / 1024 ))
CPU_CORES=$(nproc || echo 1)
echo "System resources detected: CPU_CORES=${CPU_CORES}, TOTAL_MEM_MB=${TOTAL_MEM_MB}MB"

# -----------------------
# Auto-calc PHP sizing heuristic
# -----------------------
RESERVE_MB=$(( (TOTAL_MEM_MB * 30) / 100 ))
if [ "${RESERVE_MB}" -lt 1024 ]; then RESERVE_MB=1024; fi

if [ "${TOTAL_MEM_MB}" -lt 4096 ]; then
  MEM_LIMIT_MB=128
elif [ "${TOTAL_MEM_MB}" -lt 8192 ]; then
  MEM_LIMIT_MB=256
elif [ "${TOTAL_MEM_MB}" -lt 16384 ]; then
  MEM_LIMIT_MB=512
elif [ "${TOTAL_MEM_MB}" -lt 32768 ]; then
  MEM_LIMIT_MB=768
else
  MEM_LIMIT_MB=1024
fi

PHP_CHILD_MEM_MB=${PHP_CHILD_MEM_MB:-${MEM_LIMIT_MB}}
AVAILABLE_FOR_PHP_MB=$(( TOTAL_MEM_MB - RESERVE_MB ))
if [ "${AVAILABLE_FOR_PHP_MB}" -lt 256 ]; then AVAILABLE_FOR_PHP_MB=256; fi

PM_BY_MEM=$(( AVAILABLE_FOR_PHP_MB / PHP_CHILD_MEM_MB ))
PM_BY_CPU=$(( CPU_CORES * 12 ))

PM_MAX_CHILDREN=$PM_BY_MEM
if [ "${PM_BY_CPU}" -lt "${PM_MAX_CHILDREN}" ]; then PM_MAX_CHILDREN=${PM_BY_CPU}; fi
if [ "${PM_MAX_CHILDREN}" -lt 4 ]; then PM_MAX_CHILDREN=4; fi
if [ "${PM_MAX_CHILDREN}" -gt 500 ]; then PM_MAX_CHILDREN=500; fi

export MEM_LIMIT_MB PHP_CHILD_MEM_MB PM_MAX_CHILDREN AVAILABLE_FOR_PHP_MB

# Derived upload values
UPLOAD_MAX="${UPLOAD_MAX_MB}M"
POST_MAX_MB=$(( UPLOAD_MAX_MB + 32 ))
POST_MAX="${POST_MAX_MB}M"
MEM_LIMIT="${MEM_LIMIT_MB}M"
PHP_MAX_EXEC_TIME=${PHP_MAX_EXEC_TIME:-3600}
PHP_MAX_INPUT_TIME=${PHP_MAX_INPUT_TIME:-3600}

echo "Upload settings: upload_max_filesize=${UPLOAD_MAX}, post_max_size=${POST_MAX}, memory_limit=${MEM_LIMIT}"
echo "Auto-sizing: pm.max_children=${PM_MAX_CHILDREN} (MEM=${MEM_LIMIT_MB}MB per child estimate=${PHP_CHILD_MEM_MB}MB)"

# -----------------------
# Basic packages and tools
# -----------------------
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get upgrade -y
apt-get install -y ca-certificates apt-transport-https lsb-release gnupg curl wget software-properties-common unzip git rsync pwgen

# -----------------------
# PHP repo & packages per Moodle docs (guarded by INSTALL_PHP_VERSION)
# -----------------------
if [ "${INSTALL_PHP_VERSION}" = "yes" ]; then
  if ! apt-cache policy | grep -q "ondrej/php"; then
    add-apt-repository -y ppa:ondrej/php
    apt-get update
  fi

  PHP_PACKAGES=(
    "php${PHP_VERSION}-fpm" "php${PHP_VERSION}-cli"
    "php${PHP_VERSION}-curl" "php${PHP_VERSION}-zip" "php${PHP_VERSION}-gd"
    "php${PHP_VERSION}-xml" "php${PHP_VERSION}-intl" "php${PHP_VERSION}-mbstring"
    "php${PHP_VERSION}-xmlrpc" "php${PHP_VERSION}-soap" "php${PHP_VERSION}-bcmath"
    "php${PHP_VERSION}-exif" "php${PHP_VERSION}-ldap" "php${PHP_VERSION}-mysql"
    "php${PHP_VERSION}-redis"
  )
  apt-get install -y "${PHP_PACKAGES[@]}"
else
  echo "INSTALL_PHP_VERSION=no: skipping PHP install."
fi

# -----------------------
# Apache install & modules
# -----------------------
apt-get install -y apache2 libapache2-mod-fcgid
# Only toggle MPM mods if allowed
if [ "${TUNE_GLOBAL_APACHE}" = "yes" ]; then
  a2dismod mpm_prefork || true
  a2enmod mpm_event || true
else
  echo "TUNE_GLOBAL_APACHE=no: not switching Apache MPMs."
fi
a2enmod proxy_fcgi setenvif rewrite headers proxy proxy_http ssl remoteip || true
systemctl enable --now apache2

# -----------------------
# MariaDB
# -----------------------
apt-get install -y mariadb-server mariadb-client
systemctl enable --now mariadb

# -----------------------
# Redis
# -----------------------
apt-get install -y redis-server
systemctl enable --now redis-server

# -----------------------
# Tune Redis maxmemory (safe fraction)
# -----------------------
RESERVE_MB=1024
if [ "${TOTAL_MEM_MB}" -lt 2048 ]; then REDIS_TARGET_MB=$(( TOTAL_MEM_MB / 3 )); else REDIS_TARGET_MB=$(( (TOTAL_MEM_MB - RESERVE_MB) / 3 )); fi
[ "${REDIS_TARGET_MB}" -lt 128 ] && REDIS_TARGET_MB=128
sed -i "s/^#\?maxmemory .*/maxmemory ${REDIS_TARGET_MB}mb/" /etc/redis/redis.conf || echo "maxmemory ${REDIS_TARGET_MB}mb" >> /etc/redis/redis.conf
sed -i "s/^#\?maxmemory-policy .*/maxmemory-policy volatile-lru/" /etc/redis/redis.conf || true
systemctl restart redis-server || true

# -----------------------
# PHP-FPM pool tuning (apply pm.max_children etc) if allowed by TUNE_GLOBAL_PHP
# -----------------------
PHPFPM_POOL="/etc/php/${PHP_VERSION}/fpm/pool.d/www.conf"
if [ "${TUNE_GLOBAL_PHP}" = "yes" ]; then
  if [ -f "${PHPFPM_POOL}" ]; then
    sed -i "s/^pm = .*$/pm = dynamic/" "${PHPFPM_POOL}" || true
    if grep -q "^pm.max_children" "${PHPFPM_POOL}"; then
      sed -ri "s~^pm.max_children\s*=.*~pm.max_children = ${PM_MAX_CHILDREN}~" "${PHPFPM_POOL}"
    else
      echo "pm.max_children = ${PM_MAX_CHILDREN}" >> "${PHPFPM_POOL}"
    fi

    START_SERVERS=$(( PM_MAX_CHILDREN / 4 )); [ "${START_SERVERS}" -lt 2 ] && START_SERVERS=2
    MIN_SPARE=$(( PM_MAX_CHILDREN / 8 )); [ "${MIN_SPARE}" -lt 1 ] && MIN_SPARE=1
    MAX_SPARE=$(( PM_MAX_CHILDREN / 4 ))
    grep -q "^pm.start_servers" "${PHPFPM_POOL}" && sed -ri "s~^pm.start_servers\s*=.*~pm.start_servers = ${START_SERVERS}~" "${PHPFPM_POOL}" || echo "pm.start_servers = ${START_SERVERS}" >> "${PHPFPM_POOL}"
    grep -q "^pm.min_spare_servers" "${PHPFPM_POOL}" && sed -ri "s~^pm.min_spare_servers\s*=.*~pm.min_spare_servers = ${MIN_SPARE}~" "${PHPFPM_POOL}" || echo "pm.min_spare_servers = ${MIN_SPARE}" >> "${PHPFPM_POOL}"
    grep -q "^pm.max_spare_servers" "${PHPFPM_POOL}" && sed -ri "s~^pm.max_spare_servers\s*=.*~pm.max_spare_servers = ${MAX_SPARE}~" "${PHPFPM_POOL}" || echo "pm.max_spare_servers = ${MAX_SPARE}" >> "${PHPFPM_POOL}"
    systemctl restart "php${PHP_VERSION}-fpm" || true
  fi
else
  echo "TUNE_GLOBAL_PHP=no: skipping global PHP-FPM pool tuning."
fi

# -----------------------
# Apache MPM tuning (if allowed)
# -----------------------
APACHE_MPM_CONF="/etc/apache2/mods-available/mpm_event.conf"
MAX_REQUEST_WORKERS=$(( PM_MAX_CHILDREN * 2 ))
[ "${MAX_REQUEST_WORKERS}" -lt 50 ] && MAX_REQUEST_WORKERS=50
if [ "${TUNE_GLOBAL_APACHE}" = "yes" ]; then
  cp -n "${APACHE_MPM_CONF}" "${APACHE_MPM_CONF}.bak" || true
  awk -v mrw="${MAX_REQUEST_WORKERS}" -v start="${START_SERVERS}" -v minsp="${MIN_SPARE}" -v maxsp="${MAX_SPARE}" '
  BEGIN{ins=0}
  {print}
  $0 ~ /<IfModule mpm_event_module>/ {ins=1}
  ins==1 && $0 ~ /<\/IfModule>/ {print "    StartServers              " start; print "    MinSpareThreads           " minsp; print "    MaxSpareThreads           " maxsp; print "    MaxRequestWorkers         " mrw; ins=0}
  ' "${APACHE_MPM_CONF}" > "${APACHE_MPM_CONF}.tmp" && mv "${APACHE_MPM_CONF}.tmp" "${APACHE_MPM_CONF}" || true
  systemctl restart apache2 || true
else
  echo "TUNE_GLOBAL_APACHE=no: not changing mpm_event.conf / MaxRequestWorkers."
fi

# -----------------------
# Kernel / sysctl tuning (if allowed)
# -----------------------
SYSCTL_FILE="/etc/sysctl.d/99-moodle-tuning.conf"
if [ "${TUNE_SYSCTL}" = "yes" ]; then
  cat > "${SYSCTL_FILE}" <<SYSCTL
# Moodle networking tuning
net.core.somaxconn = 65535
net.core.netdev_max_backlog = 5000
net.ipv4.tcp_max_syn_backlog = 4096
net.ipv4.tcp_rmem = 4096 87380 6291456
net.ipv4.tcp_wmem = 4096 65536 6291456
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_fin_timeout = 30
net.ipv4.tcp_tw_reuse = 1
vm.swappiness = 10
SYSCTL
  sysctl --system || true
  if modprobe tcp_bbr 2>/dev/null; then sysctl -w net.core.default_qdisc=fq || true; sysctl -w net.ipv4.tcp_congestion_control=bbr || true; fi
else
  echo "TUNE_SYSCTL=no: skipping system-wide kernel/network tuning."
fi

# -----------------------
# Create Moodle directories, download code if missing
# -----------------------
if [ ! -d "${MOODLE_DIR}" ] || [ -z "$(ls -A "${MOODLE_DIR}" 2>/dev/null || true)" ]; then
  mkdir -p "${MOODLE_DIR}"
  chown -R "${WWW_USER}:${WWW_GROUP}" "${MOODLE_DIR}"
  cd /tmp
  if ! git clone --depth 1 -b MOODLE_401_STABLE https://github.com/moodle/moodle.git moodle-tmp 2>/dev/null; then
    git clone --depth 1 https://github.com/moodle/moodle.git moodle-tmp
  fi
  rsync -a moodle-tmp/ "${MOODLE_DIR}/"
  chown -R "${WWW_USER}:${WWW_GROUP}" "${MOODLE_DIR}"
  rm -rf moodle-tmp
fi

# Ensure public directory
mkdir -p "${MOODLE_PUBLIC_DIR}"
chown -R "${WWW_USER}:${WWW_GROUP}" "${MOODLE_DIR}" "${MOODLEDATA}" || true

# -----------------------
# Apache vhost (DocumentRoot -> /var/www/moodle/public, FallbackResource /r.php)
# -----------------------
DOCROOT="${MOODLE_PUBLIC_DIR}"
if [ ! -f "${APACHE_VHOST}" ]; then
  cat > "${APACHE_VHOST}" <<APACHEV
<VirtualHost *:80>
    ServerName $(echo "${MOODLE_WWWROOT}" | sed -E 's#^https?://##' | sed -E 's#/.*$##')
    ServerAlias www.$(echo "${MOODLE_WWWROOT}" | sed -E 's#^https?://##' | sed -E 's#/.*$##')

    DocumentRoot ${DOCROOT}

    <Directory ${MOODLE_DIR}>
        Options FollowSymLinks
        AllowOverride None
        Require all granted
        DirectoryIndex index.php index.html
        FallbackResource /r.php
    </Directory>

    <FilesMatch "\.php$">
        SetHandler "proxy:unix:/run/php/php${PHP_VERSION}-fpm.sock|fcgi://localhost/"
    </FilesMatch>

    ErrorLog \${APACHE_LOG_DIR}/moodle_error.log
    CustomLog \${APACHE_LOG_DIR}/moodle_access.log combined
</VirtualHost>
APACHEV
  a2ensite "$(basename "${APACHE_VHOST}")" || true
  a2dissite 000-default.conf || true
  systemctl reload apache2 || true
else
  if ! grep -q "^\\s*ServerName" "${APACHE_VHOST}"; then
    sed -i "0,/<VirtualHost/{s#<VirtualHost#<VirtualHost\n    ServerName $(echo "${MOODLE_WWWROOT}" | sed -E 's#^https?://##' | sed -E 's#/.*$##')#" "${APACHE_VHOST}" || true
    systemctl.reload apache2 || true || true
  fi
fi

# -----------------------
# PHP INI changes (FPM & CLI) - include upload/post/memory/timeouts and max_input_vars
# -----------------------
PHP_INI_FPM="/etc/php/${PHP_VERSION}/fpm/php.ini"
PHP_INI_CLI="/etc/php/${PHP_VERSION}/cli/php.ini"

for phpini in "${PHP_INI_FPM}" "${PHP_INI_CLI}"; do
  if [ -f "${phpini}" ]; then
    sed -i "s/^[ \t]*;*[ \t]*max_input_vars[ \t]*=.*/max_input_vars = 5000/" "${phpini}" || true

    if grep -q -E '^[ \t]*upload_max_filesize' "${phpini}"; then
      sed -ri "s~^[ \t]*upload_max_filesize\s*=.*~upload_max_filesize = ${UPLOAD_MAX}~" "${phpini}"
    else
      echo "upload_max_filesize = ${UPLOAD_MAX}" >> "${phpini}"
    fi

    if grep -q -E '^[ \t]*post_max_size' "${phpini}"; then
      sed -ri "s~^[ \t]*post_max_size\s*=.*~post_max_size = ${POST_MAX}~" "${phpini}"
    else
      echo "post_max_size = ${POST_MAX}" >> "${phpini}"
    fi

    if grep -q -E '^[ \t]*memory_limit' "${phpini}"; then
      sed -ri "s~^[ \t]*memory_limit\s*=.*~memory_limit = ${MEM_LIMIT}~" "${phpini}"
    else
      echo "memory_limit = ${MEM_LIMIT}" >> "${phpini}"
    fi

    if grep -q -E '^[ \t]*max_execution_time' "${phpini}"; then
      sed -ri "s~^[ \t]*max_execution_time\s*=.*~max_execution_time = ${PHP_MAX_EXEC_TIME}~" "${phpini}"
    else
      echo "max_execution_time = ${PHP_MAX_EXEC_TIME}" >> "${phpini}"
    fi

    if grep -q -E '^[ \t]*max_input_time' "${phpini}"; then
      sed -ri "s~^[ \t]*max_input_time\s*=.*~max_input_time = ${PHP_MAX_INPUT_TIME}~" "${phpini}"
    else
      echo "max_input_time = ${PHP_MAX_INPUT_TIME}" >> "${phpini}"
    fi
  fi
done

systemctl reload "php${PHP_VERSION}-fpm" || systemctl restart "php${PHP_VERSION}-fpm" || true

# -----------------------
# Ensure php_admin_value entries in PHP-FPM pool (idempotent)
# -----------------------
if [ -f "${PHPFPM_POOL}" ]; then
  set_or_replace_php_admin() {
    local key="$1" val="$2" poolfile="$3"
    local sedval
    sedval=$(printf '%s\n' "$val" | sed -e 's/[\/&]/\\&/g')
    if grep -q "^[ \t]*php_admin_value\\[${key}\\]" "${poolfile}"; then
      sed -ri "s~^[ \t]*php_admin_value\\[${key}\\]\s*=.*~php_admin_value[${key}] = ${sedval}~" "${poolfile}"
    else
      echo "php_admin_value[${key}] = ${val}" >> "${poolfile}"
    fi
  }

  set_or_replace_php_admin "upload_max_filesize" "${UPLOAD_MAX}" "${PHPFPM_POOL}"
  set_or_replace_php_admin "post_max_size" "${POST_MAX}" "${PHPFPM_POOL}"
  set_or_replace_php_admin "memory_limit" "${MEM_LIMIT}" "${PHPFPM_POOL}"
  set_or_replace_php_admin "max_execution_time" "${PHP_MAX_EXEC_TIME}" "${PHPFPM_POOL}"
  set_or_replace_php_admin "max_input_time" "${PHP_MAX_INPUT_TIME}" "${PHPFPM_POOL}"

  systemctl reload "php${PHP_VERSION}-fpm" || systemctl restart "php${PHP_VERSION}-fpm" || true
fi

# -----------------------
# Apache vhost: ensure LimitRequestBody is configured to allow the upload size
# -----------------------
LIMIT_BYTES=$(( UPLOAD_MAX_MB * 1024 * 1024 ))
if [ -f "${APACHE_VHOST}" ]; then
  if grep -q -E '^[ \t]*LimitRequestBody' "${APACHE_VHOST}"; then
    sed -ri "s~^[ \t]*LimitRequestBody\s+.*~    LimitRequestBody ${LIMIT_BYTES}~" "${APACHE_VHOST}"
  else
    sed -ri "0,/<VirtualHost/ s#<VirtualHost([^>]*)>#<VirtualHost\\1>\\n    LimitRequestBody ${LIMIT_BYTES}#" "${APACHE_VHOST}" || echo "    LimitRequestBody ${LIMIT_BYTES}" >> "${APACHE_VHOST}"
  fi
  systemctl reload apache2 || systemctl restart apache2 || true
fi

# -----------------------
# Composer & vendor install
# -----------------------
if ! command -v composer >/dev/null 2>&1; then
  curl -sS https://getcomposer.org/installer -o /tmp/composer-setup.php
  php /tmp/composer-setup.php --install-dir=/usr/local/bin --filename=composer || true
fi

COMPOSER_CACHE_DIR="/var/www/.cache/composer"
mkdir -p "${COMPOSER_CACHE_DIR}"
chown -R "${WWW_USER}:${WWW_GROUP}" "${COMPOSER_CACHE_DIR}"
chmod 750 "${COMPOSER_CACHE_DIR}"

if [ -d "${MOODLE_DIR}" ] && [ -f "${MOODLE_DIR}/composer.json" ] && [ ! -d "${MOODLE_DIR}/vendor" ]; then
  echo "Running composer install as ${WWW_USER}..."
  sudo -u "${WWW_USER}" env COMPOSER_CACHE_DIR="${COMPOSER_CACHE_DIR}" composer install --no-dev --classmap-authoritative --working-dir="${MOODLE_DIR}" || true
  chown -R "${WWW_USER}:${WWW_GROUP}" "${MOODLE_DIR}/vendor" || true
fi

# -----------------------
# Ensure moodledata and permissions
# -----------------------
mkdir -p "${MOODLEDATA}"
chown -R "${WWW_USER}:${WWW_GROUP}" "${MOODLEDATA}"
chmod 2770 "${MOODLEDATA}"

# -----------------------
# Moove theme installation (idempotent) - placed before CLI installer so install.php can register it
# -----------------------
THEME_DIR="${MOODLE_DIR}/theme"
MOOVE_DIR="${THEME_DIR}/moove"

if [ "${INSTALL_MOOVE}" = "yes" ]; then
  mkdir -p "${THEME_DIR}"
  if [ -d "${MOOVE_DIR}" ]; then
    echo "Moove already present at ${MOOVE_DIR} — attempting to update (branch ${MOODLE_BRANCH})"
    cd "${MOOVE_DIR}" || true
    git fetch --all --tags || true
    if git rev-parse --verify "origin/${MOODLE_BRANCH}" >/dev/null 2>&1; then
      git checkout "${MOODLE_BRANCH}" || git checkout -B "${MOODLE_BRANCH}" "origin/${MOODLE_BRANCH}" || true
      git pull --ff-only origin "${MOODLE_BRANCH}" || true
    else
      echo "Branch ${MOODLE_BRANCH} not found; keeping existing code."
    fi
  else
    echo "Cloning Moove theme into ${MOOVE_DIR} (branch ${MOODLE_BRANCH})"
    git clone --depth 1 --branch "${MOODLE_BRANCH}" "${MOOVE_REPO}" "${MOOVE_DIR}" 2>/dev/null || git clone --depth 1 "${MOOVE_REPO}" "${MOOVE_DIR}"
  fi

  chown -R "${WWW_USER}:${WWW_GROUP}" "${MOOVE_DIR}"
  find "${MOOVE_DIR}" -type d -exec chmod 0755 {} \; || true
  find "${MOOVE_DIR}" -type f -exec chmod 0644 {} \; || true
else
  echo "INSTALL_MOOVE=no: skipping automated Moove theme code deployment."
fi

# -----------------------
# DB credentials & creation (idempotent)
# -----------------------
mkdir -p "$(dirname "${DB_PASS_FILE}")"
if [ -f "${DB_PASS_FILE}" ]; then
  MOODLE_DB_PASS="$(cat "${DB_PASS_FILE}")"
else
  MOODLE_DB_PASS="$(pwgen -s 18 1)"
  echo "${MOODLE_DB_PASS}" > "${DB_PASS_FILE}"
  chmod 600 "${DB_PASS_FILE}"
fi

if [ -f "${ADMIN_PASS_FILE}" ]; then
  MOODLE_ADMIN_PASS="$(cat "${ADMIN_PASS_FILE}")"
else
  MOODLE_ADMIN_PASS="$(pwgen -s 16 1)"
  echo "${MOODLE_ADMIN_PASS}" > "${ADMIN_PASS_FILE}"
  chmod 600 "${ADMIN_PASS_FILE}"
fi

if ! mysql -u root -e "SELECT 1;" >/dev/null 2>&1; then
  if sudo mysql -e "SELECT 1;" >/dev/null 2>&1; then MYSQL_EXEC="sudo mysql -u root"; else MYSQL_EXEC="mysql -u root"; fi
else
  MYSQL_EXEC="mysql -u root"
fi

"${MYSQL_EXEC}" -e "CREATE DATABASE IF NOT EXISTS \`${MOODLE_DB}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
"${MYSQL_EXEC}" -e "CREATE USER IF NOT EXISTS '${MOODLE_DB_USER}'@'localhost' IDENTIFIED BY '${MOODLE_DB_PASS}';"
"${MYSQL_EXEC}" -e "GRANT ALL PRIVILEGES ON \`${MOODLE_DB}\`.* TO '${MOODLE_DB_USER}'@'localhost'; FLUSH PRIVILEGES;"
echo "Created DB/user if missing. Password stored at ${DB_PASS_FILE}"

# -----------------------
# Configure PHP sessions to Redis (optional)
# -----------------------
if [ -f "${PHP_INI_FPM}" ]; then
  if ! grep -q "^session.save_handler\s*=\s*redis" "${PHP_INI_FPM}"; then
    sed -i "s/^;*\s*session.save_handler\s*=.*/session.save_handler = redis/" "${PHP_INI_FPM}" || echo "session.save_handler = redis" >> "${PHP_INI_FPM}"
    sed -i "s@^;*\s*session.save_path\s*=.*@session.save_path = \"tcp://127.0.0.1:6379\"@" "${PHP_INI_FPM}" || echo "session.save_path = \"tcp://127.0.0.1:6379\"" >> "${PHP_INI_FPM}"
    systemctl restart "php${PHP_VERSION}-fpm" || true
  fi
fi

# -----------------------
# CLI Moodle install (non-interactive) if not already installed
# -----------------------
if [ -f "${MOODLE_DIR}/config.php" ]; then
  echo "Moodle already installed; skipping CLI installer."
  # Even if installed, ensure theme registration steps run
  if [ "${INSTALL_MOOVE}" = "yes" ] && [ -f "${MOODLE_DIR}/admin/cli/upgrade.php" ]; then
    echo "Registering/updating Moove theme via CLI (site already installed)..."
    cd "${MOODLE_DIR}"
    sudo -u "${WWW_USER}" php admin/cli/upgrade.php --non-interactive || echo "upgrade.php returned non-zero (check logs)"
    sudo -u "${WWW_USER}" php admin/cli/build_theme_css.php --themes=moove || true
    sudo -u "${WWW_USER}" php admin/cli/purge_caches.php || true
    sudo -u "${WWW_USER}" php admin/cli/cfg.php --name=theme --set=moove || true
  fi
else
  echo "Running Moodle CLI installer (non-interactive) as ${WWW_USER}..."
  sudo -u "${WWW_USER}" /usr/bin/php "${MOODLE_DIR}/admin/cli/install.php" \
    --agree-license --wwwroot="${MOODLE_WWWROOT}" --dataroot="${MOODLEDATA}" \
    --dbtype=mysqli --dbhost=localhost --dbname="${MOODLE_DB}" --dbuser="${MOODLE_DB_USER}" --dbpass="${MOODLE_DB_PASS}" \
    --fullname="${MOODLE_FULLNAME}" --shortname="${MOODLE_SHORTNAME}" \
    --adminuser="${MOODLE_ADMINUSER}" --adminpass="${MOODLE_ADMIN_PASS}" --adminemail="${MOODLE_ADMINEMAIL}" \
    --non-interactive --allow-unstable || true
  chown "${WWW_USER}:${WWW_GROUP}" "${MOODLE_DIR}/config.php" || true

  # After install, register Moove if requested
  if [ "${INSTALL_MOOVE}" = "yes" ] && [ -f "${MOODLE_DIR}/admin/cli/upgrade.php" ]; then
    echo "Registering Moove theme via CLI after fresh install..."
    cd "${MOODLE_DIR}"
    sudo -u "${WWW_USER}" php admin/cli/upgrade.php --non-interactive || echo "upgrade.php returned non-zero (check logs)"
    sudo -u "${WWW_USER}" php admin/cli/build_theme_css.php --themes=moove || true
    sudo -u "${WWW_USER}" php admin/cli/purge_caches.php || true
    sudo -u "${WWW_USER}" php admin/cli/cfg.php --name=theme --set=moove || true
  fi
fi

# -----------------------
# systemd timer for Moodle cron
# -----------------------
if [ ! -f /etc/systemd/system/moodle-cron.service ]; then
  cat >/etc/systemd/system/moodle-cron.service <<'SERVICE'
[Unit]
Description=Moodle cron job
After=network.target

[Service]
Type=oneshot
User=www-data
Group=www-data
ExecStart=/usr/bin/php /var/www/moodle/admin/cli/cron.php
SERVICE

  cat >/etc/systemd/system/moodle-cron.timer <<'TIMER'
[Unit]
Description=Run Moodle cron every minute

[Timer]
OnBootSec=1min
OnUnitActiveSec=1min
AccuracySec=1s

[Install]
WantedBy=timers.target
TIMER

  systemctl daemon-reload
  systemctl enable --now moodle-cron.timer
fi

# -----------------------
# Certbot (only if domain, skip for localhost)
# -----------------------
get_domain(){ echo "${MOODLE_WWWROOT}" | sed -E 's#^https?://##' | sed -E 's#/.*$##'; }
DOMAIN="$(get_domain)"
is_localhost_or_ip() {
  case "$1" in localhost|127.*|::1|0.0.0.0) return 0 ;; *) if echo "$1" | grep -Eq '^([0-9]{1,3}\.){3}[0-9]{1,3}$'; then return 0; else return 1; fi ;; esac
}
if ! is_localhost_or_ip "${DOMAIN}"; then
  apt-get install -y certbot python3-certbot-apache || true
  if certbot certificates | grep -E "Domains:.*\b${DOMAIN}\b" >/dev/null 2>&1; then
    echo "Certificate already present for ${DOMAIN}"
  else
    echo "Attempting to obtain certificate for ${DOMAIN} via certbot (apache plugin)."
    certbot --apache -d "${DOMAIN}" --non-interactive --agree-tos --email "${MOODLE_ADMINEMAIL}" --redirect || echo "Certbot failed; check DNS/ports"
  fi
else
  echo "Skipping certbot for localhost/IP: ${DOMAIN}"
fi

# -----------------------
# mysqltuner + safe-apply (guarded by RUN_MYSQLTUNER)
# -----------------------
if [ "${RUN_MYSQLTUNER}" = "yes" ]; then
  if [ ! -x "${MYSQLTUNER_BIN}" ]; then
    apt-get install -y perl libdbi-perl libconfig-inifiles-perl || true
    curl -fsSL https://raw.githubusercontent.com/major/MySQLTuner-perl/master/mysqltuner.pl -o "${MYSQLTUNER_BIN}"
    chmod +x "${MYSQLTUNER_BIN}"
  fi
  "${MYSQLTUNER_BIN}" --quiet > /var/log/mysqltuner.last || true
  grep -E "Max Connections|table_open_cache|tmp_table_size|max_heap_table_size|innodb_buffer_pool_size|innodb_log_file_size" -i /var/log/mysqltuner.last > /var/log/mysqltuner_suggestions.txt || true

  SUGG="/var/log/mysqltuner_suggestions.txt"
  declare -A NEW_CONF
  if [ -s "${SUGG}" ]; then
    if grep -qi "innodb_buffer_pool_size" "${SUGG}"; then vbp=$(grep -i "innodb_buffer_pool_size" "${SUGG}" | head -n1 | sed -E 's/[^0-9]*([0-9]+).*/\1/'); [ -n "${vbp}" ] && NEW_CONF["innodb_buffer_pool_size"]="${vbp}M"; fi
    if grep -qi "Max Connections" "${SUGG}"; then vconn=$(grep -i "Max Connections" "${SUGG}" | sed -E 's/.*: *([0-9]+).*/\1/' | head -n1); [ -n "${vconn}" ] && NEW_CONF["max_connections"]="${vconn}"; fi
    if grep -qi "table_open_cache" "${SUGG}"; then vtable=$(grep -i "table_open_cache" "${SUGG}" | sed -E 's/.*: *([0-9]+).*/\1/' | head -n1); [ -n "${vtable}" ] && NEW_CONF["table_open_cache"]="${vtable}"; fi
    if grep -Eqi "tmp_table_size|max_heap_table_size" "${SUGG}"; then vtmp=$(grep -E -i "tmp_table_size|max_heap_table_size" "${SUGG}" | head -n1 | sed -E 's/.*: *([0-9]+M?).*/\1/'); if [ -n "${vtmp}" ]; then [[ "${vtmp}" =~ ^[0-9]+$ ]] && vtmp="${vtmp}M"; NEW_CONF["tmp_table_size"]="${vtmp}"; NEW_CONF["max_heap_table_size"]="${vtmp}"; fi; fi
    if grep -qi "innodb_log_file_size" "${SUGG}"; then echo "mysqltuner suggests innodb_log_file_size (NOT auto-applied)"; fi
  fi

  if [ "${#NEW_CONF[@]}" -gt 0 ]; then
    PENDING="${MARIADB_TUNE_MARKER}.pending"
    echo "# pending mysqltuner suggestions - $(date)" > "${PENDING}"
    echo "[mysqld]" >> "${PENDING}"
    for k in "${!NEW_CONF[@]}"; do echo "${k} = ${NEW_CONF[$k]}" >> "${PENDING}"; done
    chmod 644 "${PENDING}"
    mkdir -p "${BACKUP_BASE}"
    cp -a /etc/mysql/mariadb.conf.d/* "${BACKUP_BASE}/mariadb_conf_preapply_$(date +%Y%m%d_%H%M%S)/" || true

    # Snapshot: try LVM snapshot first; fallback to local mysqldump + /var/lib/mysql tar
    SNAP_MARKER="/var/log/mariadb_snapshot.ok"
    create_lvm_snapshot() {
      if ! command -v lvcreate >/dev/null 2>&1; then return 1; fi
      MYSQL_DIR="/var/lib/mysql"
      FS_SRC=$(findmnt -no SOURCE "${MYSQL_DIR}" 2>/dev/null || findmnt -no SOURCE /)
      if [[ "${FS_SRC}" != /dev/mapper/* ]]; then return 1; fi
      VGNAME=$(lvs --noheadings -o vg_name "${FS_SRC}" 2>/dev/null | awk '{print $1}' || true)
      LVNAME=$(lvs --noheadings -o lv_name "${FS_SRC}" 2>/dev/null | awk '{print $1}' || true)
      if [ -z "${VGNAME}" ] || [ -z "${LVNAME}" ]; then
        if [[ "${FS_SRC}" =~ /dev/mapper/([^-/]+)-(.+) ]]; then VGNAME="${BASH_REMATCH[1]}"; LVNAME="${BASH_REMATCH[2]}"; fi
      fi
      if [ -z "${VGNAME}" ] || [ -z "${LVNAME}" ]; then return 1; fi
      SNAPNAME="${LVNAME}_pre_mariadb_tune_$(date +%Y%m%d_%H%M%S)"
      if lvcreate -s -n "${SNAPNAME}" -L 1G "/dev/${VGNAME}/${LVNAME}" >/dev/null 2>&1; then touch "${SNAP_MARKER}"; return 0; else return 1; fi
    }
    create_local_backup() {
      TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
      mkdir -p "${BACKUP_BASE}/${TIMESTAMP}"
      DUMP_FILE="${BACKUP_BASE}/${TIMESTAMP}/all_databases_${TIMESTAMP}.sql.gz"
      FS_TAR="${BACKUP_BASE}/${TIMESTAMP}/var_lib_mysql_${TIMESTAMP}.tar.gz"
      STOPPED=false
      if systemctl is-active --quiet mariadb; then systemctl stop mariadb; STOPPED=true; fi
      if /usr/bin/mysqldump --all-databases --single-transaction --quick --lock-tables=false | gzip -c > "${DUMP_FILE}"; then tar -czf "${FS_TAR}" /var/lib/mysql || true; else $([ "${STOPPED}" = true ] && systemctl start mariadb); return 1; fi
      if [ "${STOPPED}" = true ]; then systemctl start mariadb; fi
      touch "${SNAP_MARKER}"
      return 0
    }

    if create_lvm_snapshot; then echo "LVM snapshot created."; else echo "LVM snapshot failed — creating local backup."; if ! create_local_backup; then echo "Backup failed — aborting apply."; exit 1; fi; fi

    mv -f "${PENDING}" "${MARIADB_TUNE_MARKER}"
    chmod 644 "${MARIADB_TUNE_MARKER}"
    systemctl restart mariadb
    sleep 2
    if systemctl is-active --quiet mariadb; then touch /var/log/mariadb_tune_applied.ok; echo "MariaDB restarted and tuning applied."; else echo "MariaDB failed to start after applying tuning. Restore backups and investigate."; exit 1; fi

    for k in "${!NEW_CONF[@]}"; do
      if [[ "${k}" == "max_connections" ]]; then "${MYSQL_EXEC_CMD}" -e "SET GLOBAL max_connections = ${NEW_CONF[$k]};" || true; fi
      if [[ "${k}" == "tmp_table_size" || "${k}" == "max_heap_table_size" ]]; then "${MYSQL_EXEC_CMD}" -e "SET GLOBAL ${k} = ${NEW_CONF[$k]};" || true; fi
    done
  fi
else
  echo "RUN_MYSQLTUNER=no: skipping automated MariaDB tuning."
fi

# -----------------------
# Optional: Clean up git metadata and repo cruft (idempotent)
# This block creates a backup tarball (unless CLEANUP_BACKUP=no), removes .git and common repo files,
# and writes a marker when completed.
# -----------------------
if [ "${CLEANUP_GIT}" = "yes" ]; then
  echo "=== Starting git cleanup at $(date) ===" | tee -a "${CLEANUP_LOG}"

  if [ ! -d "${MOODLE_DIR}" ]; then
    echo "Moodle directory ${MOODLE_DIR} not found — skipping cleanup." | tee -a "${CLEANUP_LOG}"
  else
    if [ "${CLEANUP_BACKUP}" = "yes" ]; then
      mkdir -p "${CLEANUP_BACKUP_DIR}"
      BACKUP_TS=$(date +%Y%m%d_%H%M%S)
      BACKUP_FILE="${CLEANUP_BACKUP_DIR}/moodle_code_backup_${BACKUP_TS}.tar.gz"

      if [ ! -f "${BACKUP_FILE}" ]; then
        echo "Creating backup tarball ${BACKUP_FILE} (excluding moodledata and node_modules)..." | tee -a "${CLEANUP_LOG}"
        tar --exclude='moodledata' --exclude='node_modules' -czf "${BACKUP_FILE}" -C "$(dirname "${MOODLE_DIR}")" "$(basename "${MOODLE_DIR}")" \
          && echo "Backup created: ${BACKUP_FILE}" | tee -a "${CLEANUP_LOG}" || { echo "Backup failed — aborting cleanup" | tee -a "${CLEANUP_LOG}"; exit 1; }
      else
        echo "Backup file ${BACKUP_FILE} already exists — skipping creation." | tee -a "${CLEANUP_LOG}"
      fi
    else
      echo "CLEANUP_BACKUP=no: skipping code backup." | tee -a "${CLEANUP_LOG}"
    fi

    MOODLE_DIR_ABS="$(readlink -f "${MOODLE_DIR}")"
    if [ -z "${MOODLE_DIR_ABS}" ] || [ "${MOODLE_DIR_ABS}" = "/" ]; then
      echo "Refusing to run cleanup because MOODLE_DIR resolves to root or empty: '${MOODLE_DIR_ABS}'" | tee -a "${CLEANUP_LOG}"
    else
      echo "Cleaning git metadata inside ${MOODLE_DIR_ABS} ..." | tee -a "${CLEANUP_LOG}"

      # Remove all .git directories
      find "${MOODLE_DIR_ABS}" -type d -name ".git" -prune -print -exec rm -rf {} + 2>/dev/null | tee -a "${CLEANUP_LOG}" || true

      # Remove common repo/CI files
      find "${MOODLE_DIR_ABS}" -maxdepth 3 -type f \( -iname ".gitignore" -o -iname ".gitattributes" -o -iname "README*" -o -iname "LICENSE*" -o -iname ".travis.yml" -o -iname "circle.yml" -o -iname ".gitmodules" \) -print -exec rm -f {} + 2>/dev/null | tee -a "${CLEANUP_LOG}" || true
      find "${MOODLE_DIR_ABS}" -maxdepth 4 -type d -iname ".github" -prune -print -exec rm -rf {} + 2>/dev/null | tee -a "${CLEANUP_LOG}" || true

      # Adjust ownership & permissions
      chown -R "${WWW_USER}:${WWW_GROUP}" "${MOODLE_DIR_ABS}" || true
      find "${MOODLE_DIR_ABS}" -type d -exec chmod 0755 {} \; 2>/dev/null || true
      find "${MOODLE_DIR_ABS}" -type f -exec chmod 0644 {} \; 2>/dev/null || true

      CLEAN_MARKER="/var/log/moodle_git_cleanup_ok"
      touch "${CLEAN_MARKER}"
      echo "Git cleanup completed at $(date). Marker: ${CLEAN_MARKER}" | tee -a "${CLEANUP_LOG}"
    fi
  fi
else
  echo "CLEANUP_GIT is not 'yes' — skipping git cleanup step." | tee -a "${CLEANUP_LOG}"
fi

# -----------------------
# Final permissions & summary
# -----------------------
chown -R "${WWW_USER}:${WWW_GROUP}" "${MOODLE_DIR}" "${MOODLEDATA}" || true
find "${MOODLE_DIR}" -type f -exec chmod 0644 {} \; || true
find "${MOODLE_DIR}" -type d -exec chmod 0755 {} \; || true

cat <<EOF

INSTALLATION & TUNING COMPLETE (summary)
 - Moodle directory: ${MOODLE_DIR}
 - Moodle public dir: ${MOODLE_PUBLIC_DIR}
 - Moodle data: ${MOODLEDATA}
 - Moodle DB: ${MOODLE_DB} / ${MOODLE_DB_USER} (password in ${DB_PASS_FILE})
 - Moodle admin: ${MOODLE_ADMINUSER} (password in ${ADMIN_PASS_FILE})
 - PHP version: ${PHP_VERSION}
 - memory_limit (php.ini): ${MEM_LIMIT}
 - per-PHP-child estimate: ${PHP_CHILD_MEM_MB} MB
 - pm.max_children (recommended/applied): ${PM_MAX_CHILDREN}
 - Redis maxmemory: ${REDIS_TARGET_MB:-unknown}MB
 - MariaDB tuning file: ${MARIADB_TUNE_MARKER} (pending/applied)
 - mysqltuner output: /var/log/mysqltuner.last
 - Backups (if created): ${BACKUP_BASE}
 - Upload limit configured: upload_max_filesize=${UPLOAD_MAX}, post_max_size=${POST_MAX}, memory_limit=${MEM_LIMIT}
 - Apache LimitRequestBody set to ${LIMIT_BYTES:-unknown} bytes
 - Moove install requested: ${INSTALL_MOOVE}
 - Moove branch used: ${MOODLE_BRANCH}
 - Git cleanup requested: ${CLEANUP_GIT}
 - Code backup dir (if created): ${CLEANUP_BACKUP_DIR}

Important notes:
 - innodb_log_file_size changes are NOT auto-applied. They require stopping mariadb and moving ib_logfile*.
 - Ensure MEM_LIMIT_MB × pm.max_children fits in available RAM. We reserved ${RESERVE_MB}MB for OS and DB.
 - Verify PHP settings:
     php -i | grep -E 'upload_max_filesize|post_max_size|memory_limit|max_execution_time|max_input_time'
   And run Moodle CLI checks:
     sudo -u ${WWW_USER} php ${MOODLE_DIR}/admin/cli/checks.php

To view credentials:
  sudo cat ${ADMIN_PASS_FILE}
  sudo cat ${DB_PASS_FILE}

EOF

exit 0

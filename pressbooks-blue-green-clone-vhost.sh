#!/usr/bin/env bash
set -e

################################################
# CONFIG (MATCHES YOUR SETUP)
################################################

OLD_DOMAIN="pressbooks.qbnox.com"
NEW_DOMAIN="spvmm.qbnox.com"

# SAME VM PATHS
BLUE_ROOT="/var/www/pressbooksoss-bedrock"
GREEN_ROOT="/var/www/pressbooksoss-bedrock-green"

WP_REL="web/wp"
BLUE_WP="$BLUE_ROOT/$WP_REL"
GREEN_WP="$GREEN_ROOT/$WP_REL"

# Apache
APACHE_SITES="/etc/apache2/sites-available"
BLUE_VHOST="pressbooks.conf"           # existing LIVE vhost
GREEN_VHOST="pressbooks-green.conf"

ADMIN_EMAIL="ugen@qbnox.com"

################################################

echo "🟦🟩 PRESSBOOKS BLUE–GREEN (CLONE VHOST)"
echo "LIVE : $OLD_DOMAIN"
echo "GREEN: $NEW_DOMAIN"
echo

#-------------------------------------------------
# 1. Enable Maintenance Mode (BLUE)
#-------------------------------------------------
echo "🔒 Enabling maintenance mode on LIVE site..."

sudo -u www-data wp maintenance-mode activate --path="$BLUE_WP"

echo "✅ Site is read-only"
echo

#-------------------------------------------------
# 2. Incremental rsync (FAST)
#-------------------------------------------------
echo "📦 Incremental rsync BLUE → GREEN..."

rsync -a --delete \
  --exclude=.git \
  --exclude=web/app/uploads/cache \
  "$BLUE_ROOT/" "$GREEN_ROOT/"

chown -R www-data:www-data "$GREEN_ROOT"

echo "✅ Files synced"
echo

#-------------------------------------------------
# 3. Update GREEN Bedrock .env
#-------------------------------------------------
echo "🛠 Updating GREEN .env..."

sed -i \
  -e "s|WP_HOME=.*|WP_HOME='https://$NEW_DOMAIN'|" \
  -e "s|WP_SITEURL=.*|WP_SITEURL='https://$NEW_DOMAIN/wp'|" \
  "$GREEN_ROOT/.env"

echo "✅ .env updated"
echo

#-------------------------------------------------
# 4. Enforce PATH-BASED Multisite (GREEN)
#-------------------------------------------------
echo "🛠 Enforcing path-based multisite..."

WP_CONFIG="$GREEN_ROOT/web/wp-config.php"

sed -i "
s/define( *'SUBDOMAIN_INSTALL'.*/define('SUBDOMAIN_INSTALL', false);/
s/define( *'DOMAIN_CURRENT_SITE'.*/define('DOMAIN_CURRENT_SITE', '$NEW_DOMAIN');/
" "$WP_CONFIG"

echo "✅ wp-config fixed"
echo

#-------------------------------------------------
# 5. Update Multisite URLs (GREEN only)
#-------------------------------------------------
echo "🌐 Updating multisite URLs..."

sudo -u www-data wp site update 1 \
  --url="https://$NEW_DOMAIN" \
  --path="$GREEN_WP"

sudo -u www-data wp search-replace \
  "https://$OLD_DOMAIN" \
  "https://$NEW_DOMAIN" \
  --network \
  --skip-columns=guid \
  --path="$GREEN_WP"

echo "✅ URLs updated"
echo

#-------------------------------------------------
# 6. CLONE Apache VHOST (KEEP HEADERS)
#-------------------------------------------------
echo "🌐 Cloning Apache vhost from BLUE → GREEN..."

BLUE_VHOST_PATH="$APACHE_SITES/$BLUE_VHOST"
GREEN_VHOST_PATH="$APACHE_SITES/$GREEN_VHOST"

cp "$BLUE_VHOST_PATH" "$GREEN_VHOST_PATH"

# Update domain + document root + logs ONLY
sed -i \
  -e "s/$OLD_DOMAIN/$NEW_DOMAIN/g" \
  -e "s|$BLUE_ROOT/web|$GREEN_ROOT/web|g" \
  -e "s|access.log|spvmm-access.log|g" \
  -e "s|error.log|spvmm-error.log|g" \
  "$GREEN_VHOST_PATH"

a2ensite "$GREEN_VHOST"
systemctl reload apache2

echo "✅ GREEN vhost enabled (headers preserved)"
echo

#-------------------------------------------------
# 7. Automated Health Checks
#-------------------------------------------------
echo "🧪 Running health checks..."

check () {
  URL=$1
  CODE=$(curl -k -s -o /dev/null -w "%{http_code}" "$URL")
  [[ "$CODE" == "200" ]] || {
    echo "❌ Health check failed: $URL ($CODE)"
    exit 1
  }
  echo "✅ $URL"
}

check "https://$NEW_DOMAIN/"
check "https://$NEW_DOMAIN/wp/wp-admin/"

echo "✅ Core health checks passed"
echo

#-------------------------------------------------
# 8. Book-Level Verification
#-------------------------------------------------
echo "📚 Verifying all books..."

BOOK_PATHS=$(sudo -u www-data wp site list \
  --path="$GREEN_WP" \
  --field=path | tail -n +2)

for BOOK in $BOOK_PATHS; do
  check "https://$NEW_DOMAIN$BOOK"
done

echo "✅ All books verified"
echo

#-------------------------------------------------
# 9. Disable Maintenance Mode (BLUE)
#-------------------------------------------------
echo "🔓 Disabling maintenance mode on LIVE site..."

sudo -u www-data wp maintenance-mode deactivate --path="$BLUE_WP"

echo "✅ Live site unlocked"
echo

#-------------------------------------------------
# 10. Final Instructions
#-------------------------------------------------
echo
echo "🎉 GREEN ENVIRONMENT READY"
echo "Preview URL: https://$NEW_DOMAIN"
echo
echo "🚦 TO GO LIVE (SECONDS):"
echo "  a2dissite $BLUE_VHOST"
echo "  a2ensite  $GREEN_VHOST"
echo "  systemctl reload apache2"
echo
echo "🔁 ROLLBACK:"
echo "  a2dissite $GREEN_VHOST"
echo "  a2ensite  $BLUE_VHOST"
echo "  systemctl reload apache2"

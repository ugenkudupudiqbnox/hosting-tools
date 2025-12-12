# Restart PHP-FPM & Apache and flush redis + WP cache
systemctl restart "php8.3-fpm"
if [[ $? -ne 0 ]] ; then 
        exit 1;
fi
systemctl restart apache2
if [[ $? -ne 0 ]] ; then
        exit 1;
fi
redis-cli FLUSHALL
if [[ $? -ne 0 ]] ; then
        exit 1;
fi
sudo -u www-data wp cache flush --path=/var/www/pressbooksoss-bedrock/web/wp
if [[ $? -ne 0 ]] ; then
        exit 1;
fi

echo "Services restarted and caches flushed."

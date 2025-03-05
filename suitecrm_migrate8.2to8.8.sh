#!/bin/bash

# Function to migrate SuiteCRM from 8.2.0 to 8.8.0

# Check and install dependencies

DOMAIN_NAME=$(grep -ri 'ServerName' /etc/apache2/sites-enabled/* | awk '!seen[$2]++ {print $2}')

HTML_DIR="/var/www/html"

FILES_COUNT=$(ls -A "$HTML_DIR" 2>/dev/null | wc -l)

if [[ "$FILES_COUNT" -eq 0 || ( "$FILES_COUNT" -eq 1 && -f "$HTML_DIR/index.html" ) ]]; then
    DOMAIN_DIR="/var/www/$DOMAIN_NAME"
    echo $DOMAIN_DIR
else
    DOMAIN_DIR="$HTML_DIR"
    echo $DOMAIN_DIR
fi

migration_suitecrm() {
    echo "Migration SuiteCRM..."
    cd /var/www/$DOMAIN_DIR/tmp/package/upgrade
    #mkdir -p scrm8_8
    #cd /var/www/scrm8_8/
    wget https://github.com/salesagility/SuiteCRM-Core/releases/download/v8.8.0/SuiteCRM-8.8.0.zip
    #unzip SuiteCRM-8.8.0.zip
    #rm SuiteCRM-8.8.0.zip
    #mkdir -p /var/www/scrm8_8/public/legacy
    #scp -rp $DOMAIN_DIR/* /var/www/scrm8_8/public/legacy/
    #cd /var/www/scrm8_8/
    cd /var/www/$DOMAIN_DIR
    chmod +x bin/console
    ./bin/console suitecrm:app:upgrade -t SuiteCRM-8.8.0
    #grep -rl "$DOMAIN_DIR" /etc/apache2/sites-enabled/$DOMAIN_NAME.conf | xargs sed -i "s#$DOMAIN_DIR#${DOMAIN_DIR}/public#g"
    ./bin/console suitecrm:app:upgrade-finalize -t SuiteCRM-8.8.0
    #./bin/console suitecrm:app:upgrade-finalize
    ./bin/console suitecrm:app:upgrade-finalize -m keep
    #cd /var/www/
    #mv $DOMAIN_DIR $DOMAIN_DIR-old7.12
    #mv /var/www/scrm8_8 $DOMAIN_DIR
    chown -R www-data:www-data $DOMAIN_DIR
    chmod -R 755 $DOMAIN_DIR
    sudo find $DOMAIN_DIR -type d -exec chmod 755 {} \;
    sudo find $DOMAIN_DIR -type f -exec chmod 644 {} \;
    sudo chmod -R 775 /$DOMAIN_DIR/cache
    sudo chmod -R 775 $DOMAIN_DIR/public/legacy/cache
    sudo chmod -R 775 $DOMAIN_DIR/public/legacy/custom
    sudo chmod -R 775 $DOMAIN_DIR/public/legacy/modules
    sudo chmod -R 775 $DOMAIN_DIR/public/legacy/upload
    sudo chmod 775 $DOMAIN_DIR/public/legacy/config.php
    sudo chmod 775 $DOMAIN_DIR/public/legacy/config_override.php
    sudo systemctl restart apache2.service
    echo "apache2 has been restarted"
}

# Function to display the main menu
main_menu() {
    while true; do
        echo "1) Migrate SuiteCRM from 8.2.0 to 8.8.0 version"
        echo "2) Exit"
        read -p "Choose an option: " choice
        case $choice in
            1) migration_suitecrm ;;
            2) echo "Exiting..."; exit 0 ;;
            *) echo "Invalid option, please try again." ;;
        esac
    done
}

# Run the main menu
main_menu

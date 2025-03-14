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
    apt install php8.3 libapache2-mod-php8.3 php8.3-cli php8.3-curl php8.3-common php8.3-intl php8.3-gd php8.3-mbstring php8.3-mysqli php8.3-pdo php8.3-mysql php8.3-xml php8.3-zip php8.3-imap php8.3-ldap php8.3-curl php8.3-soap php8.3-bcmath php8.3-opcache -y
    a2dismod php8.0
    a2enmod php8.3
    cd /var/www/$DOMAIN_DIR/tmp/package/upgrade
    wget https://github.com/salesagility/SuiteCRM-Core/releases/download/v8.8.0/SuiteCRM-8.8.0.zip
    cd /var/www/$DOMAIN_DIR
    chmod +x bin/console
    ./bin/console suitecrm:app:upgrade -t SuiteCRM-8.8.0
    ./bin/console suitecrm:app:upgrade-finalize -t SuiteCRM-8.8.0
    ./bin/console suitecrm:app:upgrade-finalize -m keep
    chown -R www-data:www-data $DOMAIN_DIR
    chmod -R 755 $DOMAIN_DIR
    find $DOMAIN_DIR -type d -exec chmod 755 {} \;
    find $DOMAIN_DIR -type f -exec chmod 644 {} \;
    chmod -R 775 /$DOMAIN_DIR/cache
    systemctl restart apache2.service
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

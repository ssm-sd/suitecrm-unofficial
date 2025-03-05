#!/bin/bash

# Script to install SuiteCRM7.12

# Check and install dependencies

detect_os() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS=$ID
        VERSION=$VERSION_ID
    else
        echo "Unable to detect OS. Only Ubuntu 24.04, 22.04, Debian 11, 12"
        exit 1
    fi

    case "$OS" in
        ubuntu|debian)
            echo "OS $OS $VERSION is supported."
            ;;
        *)
            echo "OS $OS is not supported. Exiting."
            exit 1
            ;;
    esac
}

get_input() {
    read -p "$1: " value
    echo $value
}

get_internal_ip() {
    ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v '^127' | head -n1
}


check_domain() {
    # Check if the domain resolves to an IP address
    if ! getent hosts "$DOMAIN_NAME" >/dev/null; then
        echo "Warning: The domain '$DOMAIN_NAME' does not exist or is not pointing to this server."
        echo "Please create an A record for '$domain' and point it to your server's IP address."
        return 1
    fi

    echo "The domain '$DOMAIN_NAME' exists and resolves correctly."
    return 0
}

current_ssl() {
    # Use current SSL certificates
    read -p "Please input path to your SSL-сertificate: " SSL_CERT
    read -p "Please input path to your SSL-key: " SSL_KEY
}

letsencrypt_ssl() {
    if ! command -v certbot &> /dev/null; then
        echo "Certbot is not installed. Installing..."
        apt update && apt install -y certbot python3-certbot-apache
    fi
    # certbot certonly --standalone -d "$DOMAIN" || {
    if [ ! -d "$PROJECT_DIR" ]; then
    mkdir -p $PROJECT_DIR
    fi
    certbot certonly --webroot -w $PROJECT_DIR -d "$DOMAIN" --non-interactive --agree-tos -m "your-email@example.com" || { 
        echo "Error generation, using self-signed!!"
        selfsigned_ssl
    }
}

selfsigned_ssl() {
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 -subj "/C=EU/ST=Czech/L=Ostrava/O=Domain Control Validated/CN=$DOMAIN_NAME" -keyout "/etc/ssl/private/selfsigned.key" -out "/etc/ssl/certs/selfsigned.crt"
    SSL_CERT="/etc/ssl/certs/selfsigned.crt"
    SSL_KEY="/etc/ssl/private/selfsigned.key"
}


setup_ssl() {
    while true; do
        echo "1) Use current ssl certificates"
        echo "2) Generate via Let's Encrypt"
        echo "3) Self-signed certificate"
        echo "4) Not use SSl certificates - exit"
        read -p "Choose an option: " choice
        case $choice in
            1) current_ssl; return 0 ;;
            2) letsencrypt_ssl; return 0 ;;
            3) selfsigned_ssl; return 0 ;;
            4) echo "Returning..."; return 0 ;;
            *) echo "Invalid option, please try again." ;;
        esac
    done
    
}


configure_apache_ssl() {
    local config_name="$1"
    local document_root="$2"
    local ssl_cert="$3"
    local ssl_key="$4"

    rm -rf /etc/apache2/sites-enabled/000-default.conf

    cat << EOF | tee /etc/apache2/sites-available/${config_name}.conf
    <VirtualHost *:80>
        ServerAdmin webmaster@localhost
        DocumentRoot $document_root
        ServerName $config_name

        Redirect permanent / https://$config_name/

        ErrorLog \${APACHE_LOG_DIR}/error_$config_name.log
        CustomLog \${APACHE_LOG_DIR}/access_$config_name.log combined
    </VirtualHost>

    <VirtualHost *:443>
        ServerAdmin webmaster@localhost
        DocumentRoot $document_root
        ServerName $config_name

        <Directory $document_root>
            Options Indexes FollowSymLinks MultiViews
            AllowOverride All
            Require all granted
        </Directory>

        SSLEngine on
        SSLCertificateFile $ssl_cert
        SSLCertificateKeyFile $ssl_key

        ErrorLog \${APACHE_LOG_DIR}/error_$config_name.log
        CustomLog \${APACHE_LOG_DIR}/access_$config_name.log combined
    </VirtualHost>
EOF

    ln -s /etc/apache2/sites-available/${config_name}.conf /etc/apache2/sites-enabled/${config_name}.conf
}

configure_apache_http() {
    local config_name="$1"
    local document_root="$2"

    rm -rf /etc/apache2/sites-enabled/000-default.conf

    cat << EOF | tee /etc/apache2/sites-available/${config_name}.conf
    <VirtualHost *:80>
        ServerAdmin webmaster@localhost
        DocumentRoot $document_root
        ServerName $config_name

        <Directory $document_root>
            Options Indexes FollowSymLinks MultiViews
            AllowOverride All
            Require all granted
        </Directory>

        ErrorLog \${APACHE_LOG_DIR}/error_$config_name.log
        CustomLog \${APACHE_LOG_DIR}/access_$config_name.log combined
    </VirtualHost>
EOF

    ln -s /etc/apache2/sites-available/${config_name}.conf /etc/apache2/sites-enabled/${config_name}.conf
}

install_suitecrm() {
    echo "Installing SuiteCRM..."
    # Ask user for domain or IP
    read -p "Do you want to use a domain name? (y/n): " use_domain
        if [[ "$use_domain" == "y" ]]; then
            DOMAIN_NAME=$(get_input "Enter your domain name")
            if check_domain "$DOMAIN_NAME"; then
                echo "Proceeding with further setup..."
                else
                    echo "Setup aborted due to missing DNS record."
                exit 1
            fi
            PROJECT_DIR="/var/www/$DOMAIN_NAME"
            setup_ssl
        else
            server_name=$(get_internal_ip)
            PROJECT_DIR="/var/www/html"
            echo "Using server IP: $server_name"
        fi
    
    CONFIG_NAME="${DOMAIN_NAME:-$server_name}"
    if [[ -z "$CONFIG_NAME" ]]; then
        echo "Error: variables DOMAIN_NAME and server_name not set!" >&2
        exit 1
    fi

    # User input collection
    db_user=$(get_input "Enter your MariaDB username")
    db_pass=$(get_input "Enter your MariaDB password")
    
    
    # System updates and essential packages
    echo "Updating and installing essential packages..."
    sudo apt update && sudo apt upgrade -y
    sudo apt install unzip wget apache2 dialog -y

    # PHP installation and configuration
    echo "Updating and installing PHP packages..."
    sudo add-apt-repository ppa:ondrej/php -y
    sudo apt update
    sudo apt install php8.0 libapache2-mod-php8.0 php8.0-cli php8.0-curl php8.0-common php8.0-intl \
    php8.0-gd php8.0-mbstring php8.0-mysqli php8.0-pdo php8.0-mysql php8.0-xml php8.0-zip \
    php8.0-imap php8.0-ldap php8.0-curl php8.0-soap php8.0-bcmath php8.0-opcache -y

    # Apache configuration
    echo "Configuring Apache Server..."
    a2enmod rewrite headers
    a2enmod ssl

    # MariaDB installation and configuration
    echo "Installing MariaDB..."
    sudo apt install mariadb-server mariadb-client -y

    # Database setup
    echo "Configuring main database..."
    sudo mysql -u root <<EOF
    CREATE DATABASE IF NOT EXISTS suitecrm CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;
    CREATE USER IF NOT EXISTS '$db_user'@'localhost' IDENTIFIED BY '$db_pass';
    GRANT ALL PRIVILEGES ON suitecrm.* TO '$db_user'@'localhost';
    FLUSH PRIVILEGES;
EOF

    # SuiteCRM installation
    echo "Installing and configuring SuiteCRM 7.12.7..."
    mkdir -p $PROJECT_DIR
    rm -rf $PROJECT_DIR/*
    cd $PROJECT_DIR
    wget https://github.com/salesagility/SuiteCRM/releases/download/v7.12.7/SuiteCRM-7.12.7.zip
    unzip SuiteCRM-7.12.7.zip -d temp
    mv temp/SuiteCRM-7.12.7/* .
    rm -rf temp SuiteCRM-7.12.7.zip
    echo "Setting Apache configuration virtual hosts..."
    if [ "$server_name" ]; then
        echo "Setting Apache configuration virtual hosts..."
        configure_apache_http "$CONFIG_NAME" "$PROJECT_DIR"
    else
        configure_apache_ssl "$CONFIG_NAME" "$PROJECT_DIR" "$SSL_CERT" "$SSL_KEY"
    fi

    
    # PHP configuration
    tee /etc/php/8.0/apache2/conf.d/suitecrm.ini << EOF
    memory_limit = 256M
    upload_max_filesize = 100M
    post_max_size = 100M
    max_execution_time = 300
    max_input_time = 300
    error_reporting = E_ALL & ~E_DEPRECATED & ~E_STRICT & ~E_NOTICE & ~E_WARNING
    display_errors = Off
EOF

    # Directory permissions setup - More permissive for initial setup
    echo "Setting initial permissions..."
    chown -R www-data:www-data $PROJECT_DIR
    chmod -R 775 $PROJECT_DIR


    # Special directories creation and permissions
    sudo -u www-data mkdir -p $PROJECT_DIR/cache/{images,modules,pdf,upload,xml,themes}
    sudo -u www-data mkdir -p $PROJECT_DIR/custom
    sudo -u www-data touch $PROJECT_DIR/config.php
    sudo -u www-data touch $PROJECT_DIR/config_override.php
    
    # Create main .htaccess
    cat << EOF | tee $PROJECT_DIR/.htaccess
    <IfModule mod_rewrite.c>
        RewriteEngine On
        RewriteBase /
        Options +FollowSymLinks
        
        # Allow direct access to specific directories
        RewriteCond %{REQUEST_URI} ^/(cache|custom|modules|themes|upload|install)/ [OR]
        RewriteCond %{REQUEST_URI} \.(jpg|jpeg|png|gif|css|js|ico)$ [OR]
        RewriteCond %{REQUEST_URI} ^/index\.php
        RewriteRule ^ - [L]
    </IfModule>

    <FilesMatch "\.(jpg|jpeg|png|gif|css|js|ico)$">
        Allow from all
    </FilesMatch>
EOF

    # Set proper ownership and permissions for .htaccess
    sudo chown www-data:www-data  $PROJECT_DIR/.htaccess
    sudo chmod 644 $PROJECT_DIR/.htaccess
    
    # Apache configuration verification and restart
    if ! /usr/sbin/apachectl configtest; then
    echo " The error in apache configuration! Please check syntax." >&2
        exit 1
    fi
    systemctl restart apache2
    echo "Apache has been restarted"
    echo ""
    # Final security adjustments
    find $PROJECT_DIR -type d -exec chmod 755 {} \;
    find $PROJECT_DIR -type f -exec chmod 644 {} \;
    chmod -R 775 $PROJECT_DIR/cache
    chmod -R 775 $PROJECT_DIR/custom
    chmod -R 775 $PROJECT_DIR/modules
    chmod -R 775 $PROJECT_DIR/upload
    chmod 775 $PROJECT_DIR/config.php
    chmod 775 $PROJECT_DIR/config_override.php
    
    # Installation complete message
    echo ""
    echo "###################################################"
    echo "Installation completed!"
    echo "The script has finished. Before opening the web browser, you must run:"
    echo ""
    echo " sudo mysql_secure_installation "
    echo ""
    echo "To access the web installation page:"
    echo "2. Access your SuiteCRM installation at: http://$CONFIG_NAME"
    echo "3. Complete the web-based setup using these database credentials:"
    echo ""
    echo "   Database Name: suitecrm"
    echo "   Database User: $db_user"
    echo "   Database Password: $db_pass"
    echo ""
    echo "If you encounter 'Forbidden error' while opening the webpage, run in your terminal:"
    echo "sudo chmod -R 775 /var/www/html"
    echo "sudo chown -R www-data:www-data /var/www/html"
    echo ""
    echo "Installation SuiteCRM has been completed!"

}

########################################################################
# Function to update SSL certificates using Let's Encrypt
update_ssl() {
    echo "Updating SSL certificates with Let's Encrypt..."
    # Replace with your actual domain and web server reload command
    certbot renew --quiet
    systemctl reload nginx  # Change to apache2 if using Apache
    echo "SSL certificate update complete."
}

########################################################################

# Function to create a full backup of the database and website files
backup_site() {
    DB_NAME=$(get_input "Enter your MariaDB database name")
    DB_USERNAME=$(get_input "Enter your MariaDB username")
    DB_PASSWORD=$(get_input "Enter your MariaDB password")
    read -p "Please input path where located your SuiteCRM: " SITE_DIR
    TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
    BACKUP_DIR="/backup"
    BACKUP_FILE="$BACKUP_DIR/backup_$TIMESTAMP.tar.gz"
    
    echo "Creating backup..."
    mkdir -p "$BACKUP_DIR"
    mysqldump -u "$DB_USERNAME" -p"$DB_PASSWORD" "$DB_NAME" > "$BACKUP_DIR/db_backup_$TIMESTAMP.sql"
    tar -czf "$BACKUP_FILE" "$SITE_DIR" "$BACKUP_DIR/db_backup_$TIMESTAMP.sql"
    echo "Backup created: $BACKUP_FILE"
}
########################################################################

# Function to display the main menu
main_menu() {
    detect_os
    while true; do
        echo "1) Install SuiteCRM"
        echo "2) Update SSL with Let's Encrypt"
        echo "3) Create Full Backup (DB & Site)"
        echo "4) Exit"
        read -p "Choose an option: " choice
        case $choice in
            1) install_suitecrm ;;
            2) update_ssl ;;
            3) backup_site ;;
            4) echo "Exiting..."; exit 0 ;;
            *) echo "Invalid option, please try again." ;;
        esac
    done
}

# Run the main menu
main_menu

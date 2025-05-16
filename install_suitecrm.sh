#!/bin/bash

# Script to install SuiteCRM version 7 or 8 using gum for interactive prompts

# Check and install dependencies

detect_os() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS=$ID
        VERSION=$VERSION_ID
    else
        echo "Unable to detect OS. This script supports only Ubuntu 24.04, 22.04, Debian 11, 12."
        exit 1
    fi

    case "$OS" in
        ubuntu)
            if [[ "$VERSION" != "24.04" && "$VERSION" != "22.04" ]]; then
                echo "Ubuntu version $VERSION is not supported. Supported versions are 24.04 and 22.04."
                exit 1
            fi
            ;;
        debian)
            if [[ "$VERSION" != "11" && "$VERSION" != "12" ]]; then
                gum style --foreground 196 "Debian version $VERSION is not supported. Supported versions are 11 and 12."
                exit 1
            fi
            ;;
        *)
            echo "OS $OS is not supported. Exiting."
            exit 1
            ;;
    esac

    echo "OS $OS $VERSION is supported."
}

# Install dependencies
install_dependencies() {
    case "$OS" in
        ubuntu|debian)
            if [ ! -f /etc/apt/keyrings/charm.gpg ] || [ ! -f /usr/bin/gum ] || [ ! -f /usr/bin/jq ]; then
                mkdir -p /etc/apt/keyrings
                apt install curl -y
                curl -fsSL https://repo.charm.sh/apt/gpg.key | gpg --yes --dearmor -o /etc/apt/keyrings/charm.gpg
                echo "deb [signed-by=/etc/apt/keyrings/charm.gpg] https://repo.charm.sh/apt/ * *" | tee /etc/apt/sources.list.d/charm.list
                apt update && apt install -y gum jq
            fi
            ;;
    esac

    if ! command -v gum &> /dev/null; then
        gum style --foreground 196 "Dependencies installation error. Check the repositories or install them (gum and jq) manually."
        exit 1
    fi
}

get_input() {
    gum input --placeholder "$1"
}

get_internal_ip() {
    ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v '^127' | head -n1
}

check_domain() {
    # Check if the domain resolves to an IP address
    if ! getent hosts "$DOMAIN_NAME" >/dev/null; then
        gum style --foreground 196 "Warning: The domain '$DOMAIN_NAME' does not exist or is not pointing to this server."
        gum style --foreground 196 "Please create an A record for '$DOMAIN_NAME' and point it to your server's IP address."
        return 1
    fi

    gum style --foreground 46 "The domain '$DOMAIN_NAME' exists and resolves correctly."
    return 0
}

current_ssl() {
    # Use current SSL certificates
    SSL_CERT=$(gum input --placeholder "Please input path to your SSL-certificate")
    SSL_KEY=$(gum input --placeholder "Please input path to your SSL-key")
}

letsencrypt_ssl() {
    if ! command -v certbot &> /dev/null; then
        gum style --foreground 196 "Certbot is not installed. Installing..."
        apt update && apt install -y certbot python3-certbot-apache
    fi
    if [ ! -d "$PROJECT_DIR" ]; then
        mkdir -p $PROJECT_DIR
    fi
    letsencrypt_email=$(get_input "Please enter your email")
    certbot certonly --webroot -w $PROJECT_DIR -d "$DOMAIN_NAME" --non-interactive --agree-tos -m "$letsencrypt_email" || { 
        gum style --foreground 196 "Error generation, using self-signed! Please pay attention on it because it can lead to problem with installation SuiteCRM version 8.xx.xx"
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
        choice=$(gum choose "Use current ssl certificates" "Generate via Let's Encrypt" "Not use SSL certificates - exit")
        case $choice in
         "Use current ssl certificates") current_ssl; USE_SSL=true; return 0 ;;
         "Generate via Let's Encrypt") letsencrypt_ssl; USE_SSL=true; return 0 ;;
         "Not use SSL certificates - exit") gum style --foreground 46 "Returning..."; USE_SSL=false; return 0 ;;
         *) gum style --foreground 196 "Invalid option, please try again." ;;
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
            Options -Indexes +FollowSymLinks +MultiViews
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
            Options -Indexes +FollowSymLinks +MultiViews
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
    gum style --foreground 46 "Installing SuiteCRM..."
    # Ask user for domain or IP
    use_domain=$(gum confirm "Do you want to use a domain name?" && echo "y" || echo "n")
    if [[ "$use_domain" == "y" ]]; then
        DOMAIN_NAME=$(get_input "Enter your domain name")
        if check_domain "$DOMAIN_NAME"; then
            gum style --foreground 46 "Proceeding with further setup..."
        else
            gum style --foreground 196 "Setup aborted due to missing DNS record."
            exit 1
        fi
        PROJECT_DIR="/var/www/$DOMAIN_NAME"
    else
        server_name=$(get_internal_ip)
        PROJECT_DIR="/var/www/html"
        rm -rf $PROJECT_DIR/*
        gum style --foreground 46 "Using server IP: $server_name"
    fi

    CONFIG_NAME="${DOMAIN_NAME:-$server_name}"
    if [[ -z "$CONFIG_NAME" ]]; then
        gum style --foreground 196 "Error: variables DOMAIN_NAME and server_name not set!" >&2
        exit 1
    fi
    
    #fetch_releases
    
    fetch_releases() {
        local repo=$1
        curl -s "https://api.github.com/repos/salesagility/$repo/releases" | \
        jq -r '.[] | select(.prerelease == false) | .tag_name'
    }
    
    # Fetch SuiteCRM 8 releases
    gum style --foreground 46 "Fetching SuiteCRM 8 releases..."
    suitecrm8_releases=$(fetch_releases "SuiteCRM-Core")

    # Fetch SuiteCRM 7 releases
    gum style --foreground 46 "Fetching SuiteCRM 7 releases..."
    suitecrm7_releases=$(fetch_releases "SuiteCRM")

    # Combine and sort releases
    all_releases=$(echo -e "$suitecrm8_releases\n$suitecrm7_releases" | sort -Vr)

    # Let the user choose a release
    gum style --foreground 46 "Please select a SuiteCRM version to install (or press Escape to exit):"
    selected_release=$(gum choose $all_releases)
    gum style --foreground 46 "Will be use version $selected_release"

    # Check if the user pressed Escape or canceled the selection
    if [ -z "$selected_release" ]; then
        gum style --foreground 46 "No version selected. Exiting..."
        exit 1
    fi

    # Determine the repository based on the selected release
    if [[ $selected_release == v8* ]]; then
        repo="SuiteCRM-Core"
    else
        repo="SuiteCRM"
    fi

    # Download the selected release
    mkdir -p $PROJECT_DIR
    download_url="https://github.com/salesagility/$repo/releases/download/$selected_release/SuiteCRM-${selected_release#v}.zip"
    gum style --foreground 46 "Downloading SuiteCRM $selected_release from $download_url..."
    curl -L -o "$PROJECT_DIR/SuiteCRM-${selected_release#v}.zip" "$download_url"

    # Check if the download was successful
    if [ $? -eq 0 ]; then
        gum style --foreground 46 "Download completed successfully: SuiteCRM-${selected_release#v}.zip to $PROJECT_DIR"
    else
        gum style --foreground 196 "Failed to download SuiteCRM $selected_release."
    fi
    

    # User input collection
    db_name=$(get_input "Enter your MariaDB database name")
    db_user=$(get_input "Enter your MariaDB username")
    db_pass=$(get_input "Enter your MariaDB password")

    gum style --foreground 46 "Choose SSL mode instalation"
    
        setup_ssl

    # System updates and essential packages
    gum style --foreground 46 "Updating and installing essential packages..."
    #apt update && apt upgrade -y
    apt update
    apt install unzip wget curl apache2 dialog -y

    # PHP installation and configuration
    gum style --foreground 46 "Updating and installing PHP packages..."

    local php_version

    case "$OS" in
        ubuntu)
            add-apt-repository ppa:ondrej/php -y
            apt update
            ;;

        debian)
            curl -sSLo /usr/share/keyrings/deb.sury.org-php.gpg https://packages.sury.org/php/apt.gpg
            sh -c 'echo "deb [signed-by=/usr/share/keyrings/deb.sury.org-php.gpg] https://packages.sury.org/php/ $(lsb_release -sc) main" > /etc/apt/sources.list.d/php.list'
            apt update
            ;;
    esac
    
    # Extract the major and minor version numbers (e.g., 8.1.3 -> 8.1)
    local major_minor_version=$(echo ${selected_release#v} | awk -F. '{print $1"."$2}')

    # Determine the PHP version based on SuiteCRM version
    if [[ $major_minor_version == "7.10" || $major_minor_version == "7.11" ]]; then
        php_version="7.4"
    elif [[ $major_minor_version == "7.12" || $major_minor_version == "7.13" ]]; then
        php_version="8.0"
    elif [[ $major_minor_version == "7.14" ]]; then
        php_version="8.1"
    elif [[ $major_minor_version == "8.0" || $major_minor_version == "8.1" || $major_minor_version == "8.2" || $major_minor_version == "8.3" ]]; then
        php_version="8.0"
    elif [[ $major_minor_version == "8.4" || $major_minor_version == "8.5" || $major_minor_version == "8.6" || $major_minor_version == "8.7" ]]; then
        php_version="8.2"
    elif [[ $major_minor_version == "8.8" ]]; then
        php_version="8.3"
    else
        echo "Unsupported SuiteCRM version: $suitecrm_version"
        exit 1
    fi

    gum style --foreground 46 "Installing PHP $php_version..."
    apt-get update

    apt install php$php_version libapache2-mod-php$php_version php$php_version-cli php$php_version-curl php$php_version-common php$php_version-intl \
    php$php_version-gd php$php_version-mbstring php$php_version-mysqli php$php_version-pdo php$php_version-mysql php$php_version-xml php$php_version-zip \
    php$php_version-imap php$php_version-ldap php$php_version-curl php$php_version-soap php$php_version-bcmath php$php_version-opcache -y

    # Apache configuration
    gum style --foreground 46 "Configuring Apache Server..."
    a2enmod rewrite headers
    a2enmod ssl

    # MariaDB installation and configuration
    gum style --foreground 46 "Installing MariaDB..."
    apt install mariadb-server mariadb-client -y

    # Database setup
    gum style --foreground 46 "Configuring main database..."
    mysql -u root <<EOF
    CREATE DATABASE IF NOT EXISTS $db_name CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;
    CREATE USER IF NOT EXISTS '$db_user'@'localhost' IDENTIFIED BY '$db_pass';
    GRANT ALL PRIVILEGES ON $db_name.* TO '$db_user'@'localhost';
    FLUSH PRIVILEGES;
EOF

    gum style --foreground 46 "Installing and configuring SuiteCRM ${selected_release#v}..."

    if [[ $major_minor_version == *"8"* ]]; then
        cd $PROJECT_DIR
        gum style --foreground 46 "Unzip SuiteCRM veriosn ${selected_release#v}"
        unzip -q SuiteCRM-${selected_release#v}.zip
    elif [[ $major_minor_version == *"7"* ]]; then
        cd $PROJECT_DIR
        gum style --foreground 46 "Unzip SuiteCRM veriosn ${selected_release#v}"
        unzip -q SuiteCRM-${selected_release#v}.zip -d temp
        mv ${PROJECT_DIR}/temp/SuiteCRM-${selected_release#v}/* ${PROJECT_DIR}
    else
        echo "Version does not contain 7 or 8, no action taken."
    fi
    
    if [[ $major_minor_version == *"8"* ]]; then

        # Directory permissions setup version 8 - More permissive for initial setup
        gum style --foreground 46 "Setting initial permissions..."
        chown -R www-data:www-data $PROJECT_DIR
        chmod -R 755 $PROJECT_DIR

    elif [[ $major_minor_version == *"7"* ]]; then
    
        gum style --foreground 46 "Setting initial permissions..."

        # Special directories creation and permissions
        mkdir -p $PROJECT_DIR/cache/{images,modules,pdf,upload,xml,themes}
        mkdir -p $PROJECT_DIR/custom
        touch $PROJECT_DIR/config.php
        touch $PROJECT_DIR/config_override.php
        chown -R www-data:www-data $PROJECT_DIR
        chmod -R 775 $PROJECT_DIR

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
    chown www-data:www-data  $PROJECT_DIR/.htaccess
    chmod 644 $PROJECT_DIR/.htaccess
    
    else
        echo "Version does not contain 7 or 8, no action taken."
    fi

    gum style --foreground 46 "Final security adjustments"

    if [[ $major_minor_version == *"8"* ]]; then

        find $PROJECT_DIR -type d -not -perm 2755 -exec chmod 2755 {} \;
        find $PROJECT_DIR -type f -not -perm 0644 -exec chmod 0644 {} \;
        find $PROJECT_DIR ! -user www-data -exec chown www-data:www-data {} \;
        chmod +x $PROJECT_DIR/bin/console

    elif [[ $major_minor_version == *"7"* ]]; then
    
        find $PROJECT_DIR -type d -exec chmod 755 {} \;
        find $PROJECT_DIR -type f -exec chmod 644 {} \;
        chmod -R 775 $PROJECT_DIR/cache
        chmod -R 775 $PROJECT_DIR/custom
        chmod -R 775 $PROJECT_DIR/modules
        chmod -R 775 $PROJECT_DIR/upload
        chmod 775 $PROJECT_DIR/config.php
        chmod 775 $PROJECT_DIR/config_override.php
    
    else
        echo "Version does not contain 7 or 8, no action taken."
    fi

    # Determine if SSL should be used
    if [[ "$USE_SSL" == true ]]; then
        gum style --foreground 46 "Setting up Apache configuration with SSL..."
        if [[ "$major_minor_version" == *"8"* ]]; then
            PROJECT_DIR="${PROJECT_DIR}/public"
        elif [[ "$major_minor_version" == *"7"* ]]; then
            PROJECT_DIR="$PROJECT_DIR"
        fi
        configure_apache_ssl "$CONFIG_NAME" "$PROJECT_DIR" "$SSL_CERT" "$SSL_KEY"
    else
        gum style --foreground 46 "Setting up Apache configuration without SSL..."
        if [[ "$major_minor_version" == *"8"* ]]; then
            PROJECT_DIR="${PROJECT_DIR}/public"
        elif [[ "$major_minor_version" == *"7"* ]]; then
            PROJECT_DIR="$PROJECT_DIR"
        fi
        configure_apache_http "$CONFIG_NAME" "$PROJECT_DIR"
    fi

    # PHP configuration
    tee /etc/php/$php_version/apache2/conf.d/suitecrm.ini << EOF
    memory_limit = 256M
    upload_max_filesize = 100M
    post_max_size = 100M
    max_execution_time = 300
    max_input_time = 300
    error_reporting = E_ALL & ~E_DEPRECATED & ~E_STRICT & ~E_NOTICE & ~E_WARNING
    display_errors = Off
EOF

    # Apache configuration verification and restart
    if ! /usr/sbin/apachectl configtest; then
        gum style --foreground 196 "The error in apache configuration! Please check syntax." >&2
        exit 1
    fi
    systemctl restart apache2
    gum style --foreground 46 "Apache has been restarted"

    gum style --foreground 46 "Setting Apache configuration virtual hosts..."

    # Installation complete
    gum style --foreground 46 ""
    gum style --foreground 46 "###################################################"
    gum style --foreground 46 "Installation SuiteCRM has been completed!"
    gum style --foreground 46 "The script has finished. Before opening the web browser, you can run:"
    gum style --foreground 46 ""
    gum style --foreground 46 "To access the web installation page:"
    gum style --foreground 46 "2. Access your SuiteCRM installation at: http://$CONFIG_NAME"
    gum style --foreground 46 "3. Complete the web-based setup using these database credentials:"
    gum style --foreground 46 ""
    gum style --foreground 46 " Database Name: $db_name"
    gum style --foreground 46 " Database User: $db_user"
    gum style --foreground 46 " Database Password: $db_pass"
    gum style --foreground 46 ""
    gum style --foreground 46 "If you encounter 'Forbidden error' while opening the webpage, please check permissions on project folder"
    gum style --foreground 46 ""

}

update_ssl() {
    gum style --foreground 46 "Checking for Certbot installation..."

    # Check if certbot is installed
    if ! command -v certbot &> /dev/null; then
        gum style --foreground 196 "Certbot is not installed. Please install Certbot to manage SSL certificates."
        exit 1
    fi

    gum style --foreground 46 "Certbot is installed. Proceeding with SSL certificate update..."

    # Check if there are any Let's Encrypt certificates
    if [[ ! -d /etc/letsencrypt/live ]]; then
        gum style --foreground 196 "No Let's Encrypt certificates found. Please ensure certificates are set up first."
        exit 1
    fi

    gum style --foreground 46 "Updating SSL certificates with Let's Encrypt..."

    # Attempt to renew certificates
    if certbot renew --quiet; then
        gum style --foreground 46 "SSL certificates renewed successfully."
        gum style --foreground 46 "Reloading Apache to apply changes..."
        systemctl reload apache2
        gum style --foreground 46 "Apache reloaded. SSL certificate update complete."
    else
        gum style --foreground 196 "Failed to renew SSL certificates. Please check Certbot logs for details."
        exit 1
    fi
}

backup_site() {
    DB_NAME=$(get_input "Enter your MariaDB database name")
    DB_USERNAME=$(get_input "Enter your MariaDB username")
    DB_PASSWORD=$(get_input "Enter your MariaDB password")
    SITE_DIR=$(gum input --placeholder "Please input path where located your SuiteCRM")
    TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
    BACKUP_DIR="/backup"
    BACKUP_FILE="$BACKUP_DIR/backup_$TIMESTAMP.tar.gz"

    gum style --foreground 46 "Creating backup..."
    mkdir -p "$BACKUP_DIR"
    mysqldump -u "$DB_USERNAME" -p"$DB_PASSWORD" "$DB_NAME" > "$BACKUP_DIR/db_backup_$TIMESTAMP.sql"
    tar -czf "$BACKUP_FILE" "$SITE_DIR" "$BACKUP_DIR/db_backup_$TIMESTAMP.sql"
    gum style --foreground 46 "Backup created: $BACKUP_FILE"

}

main_menu() {
    CHOICE=$(gum choose "Install SuiteCRM" "Update SSL with Let's Encrypt" "Create Full Backup (DB & Site)" "Log out")
    case "$CHOICE" in
        "Install SuiteCRM")
            install_suitecrm
            ;;
        "Update SSL with Let's Encrypt")
            update_ssl
            ;;
        "Create Full Backup (DB & Site)")
            backup_site
            ;;
        "Log out")
            echo "Exiting..."
            exit 0
            ;;
        *) 
            echo "Invalid option, please try again."
            ;;
    esac
}

# Main script logic
detect_os
install_dependencies

# Run the main menu in a loop
while true; do
    main_menu
done

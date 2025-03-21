# SuiteCRM Installation Script

This repository contains a script to automate the installation of SuiteCRM version 7.12 and migrating to version 8.2.0 on Ubuntu and Debian systems. These scripts automate the setup of necessary dependencies, web server configuration, and data migration to streamline the installation and upgrade processes.. 
The script configures necessary dependencies, sets up the web server, and optimizes permissions to ensure a smooth SuiteCRM installation.


## Supported Operating Systems

- Ubuntu 24.04, 22.04
- Debian 11, 12

## Prerequisites

Before starting the installation process, ensure you have:

1. A user with `sudo` privileges.
2. Access to the terminal.

## Installation Steps

1. **Clone this repository:**
   ```bash
   git clone <repository-url>
   cd <repository-directory>
   ```

2. **Run the installation script:**
   ```bash
   bash install_suitecrm.sh
   ```

   The script will prompt for the database username and password:
   - Enter your MariaDB username.
   - Enter your MariaDB password.

3. **Database Configuration:**
   - Execute the following command for additional security:
     ```bash
     sudo mysql_secure_installation
     ```
4. **Access SuiteCRM:**
   - Open a web browser and navigate to: `http://<your-server-ip-or-domain>`
   - Complete the web-based setup using the credentials provided by the script.
   
## Migration Steps

To migrate from SuiteCRM 7.xx to 8.2.0:

1. **Run the migration script:**
   ```bash
   bash suitecrm_migrate.sh
   ```

   - Ensure your SuiteCRM installation is backed up before starting the migration.

## Post-Installation Instructions

After completing the web-based setup, ensure that the following additional configurations are made for security and proper functionality:

- Set directory permissions:
  ```bash
  sudo chmod -R 775 <your project directory>
  sudo chown -R www-data:www-data <your project directory>
  ```

## Troubleshooting

If you encounter a "Forbidden error" while accessing the web page, run the permission commands above to correct any issues with access rights.

## Contribution

We welcome contributions! For major changes, please open an issue first to discuss what you would like to change.

## License

This project uses the [MIT License](LICENSE).

---

Please adjust the `<repository-url>` and `<repository-directory>` placeholders with the actual values related to your repository. Feel free to modify the content for any additional details specific to your project.

#!/bin/bash
set -e
exec > >(tee /var/log/user-data.log | logger -t user-data -s 2>/dev/console) 2>&1

echo "======== Install Apache, MYSQL, Wordpress  ========"

# Hardcoded values
WP_DB="wordpressdb"
WP_USER="wpuser"
WP_PASS="superstrongpassword"

# Update system
apt-get update -y
apt-get upgrade -y

# Install Apache, PHP, MySQL
apt-get install -y apache2 mysql-server php libapache2-mod-php php-mysql php-gd unzip wget curl

# Enable and start services
systemctl enable apache2 mysql
systemctl start apache2 mysql

# Configure Apache (no ServerName, works with IP)
cat <<EOF >/etc/apache2/sites-available/wordpress.conf
<VirtualHost *:80>
    DocumentRoot /var/www/html
    <Directory /var/www/html>
        AllowOverride All
    </Directory>
</VirtualHost>
EOF

a2ensite wordpress.conf
a2dissite 000-default.conf
a2enmod rewrite
systemctl reload apache2

# Secure MySQL and create WordPress DB/user
mysql -u root <<MYSQL_SCRIPT
DELETE FROM mysql.user WHERE User='';
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
FLUSH PRIVILEGES;

CREATE DATABASE ${WP_DB};
CREATE USER '${WP_USER}'@'localhost' IDENTIFIED BY '${WP_PASS}';
GRANT ALL PRIVILEGES ON ${WP_DB}.* TO '${WP_USER}'@'localhost';
FLUSH PRIVILEGES;
MYSQL_SCRIPT

# Install WordPress
cd /tmp
wget https://wordpress.org/latest.tar.gz
tar -xzf latest.tar.gz
cp -r wordpress/* /var/www/html/
rm /var/www/html/index.html
chown -R www-data:www-data /var/www/html
chmod -R 755 /var/www/html

# Configure wp-config.php
cp /var/www/html/wp-config-sample.php /var/www/html/wp-config.php
sed -i "s/database_name_here/${WP_DB}/" /var/www/html/wp-config.php
sed -i "s/username_here/${WP_USER}/" /var/www/html/wp-config.php
sed -i "s/password_here/${WP_PASS}/" /var/www/html/wp-config.php

# Add random salts from WordPress API
SALT=$(curl -s https://api.wordpress.org/secret-key/1.1/salt/)
sed -i "/AUTH_KEY/d" /var/www/html/wp-config.php
sed -i "/SECURE_AUTH_KEY/d" /var/www/html/wp-config.php
sed -i "/LOGGED_IN_KEY/d" /var/www/html/wp-config.php
sed -i "/NONCE_KEY/d" /var/www/html/wp-config.php
sed -i "/AUTH_SALT/d" /var/www/html/wp-config.php
sed -i "/SECURE_AUTH_SALT/d" /var/www/html/wp-config.php
sed -i "/LOGGED_IN_SALT/d" /var/www/html/wp-config.php
sed -i "/NONCE_SALT/d" /var/www/html/wp-config.php
echo "$SALT" >> /var/www/html/wp-config.php

# Restart Apache
systemctl restart apache2

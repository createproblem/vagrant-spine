#!/bin/bash
#
# provision.sh
#
# This file is specified in Vagrantfile and is loaded by Vagrant as the primary
# provisioning script whenever the commands `vagrant up`, `vagrant provision`,
# or `vagrant reload` are used. It provides all of the default packages and
# configurations included with Varying Vagrant Vagrants.

NODE_VERSION=7.6.0

# By storing the date now, we can calculate the duration of provisioning at the
# end of this script.
start_seconds="$(date +%s)"

# PACKAGE INSTALLATION
#
# Build a bash array to pass all of the packages we want to install to a single
# apt-get command. This avoids doing all the leg work each time a package is
# set to install. It also allows us to easily comment out or add single
# packages. We set the array as empty to begin with so that we can append
# individual packages to it as required.
apt_package_install_list=()

# Start with a bash array containing all packages we want to install in the
# virtual machine. We'll then loop through each of these and check individual
# status before adding them to the apt_package_install_list array.
apt_package_check_list=(
    # php5.6-dev
    # php5.6-fpm
    # php5.6-cli
    # php5.6-mongo
    # php5.6-redis
    # php5.6-mbstring
    # php5.6-mcrypt
    # php5.6-curl
    # php5.6-intl
    # php5.6-ftp
    # php5.6-xdebug
    # php5.6-xml
    php-dev
    php-fpm
    php-cli
    php-redis
    php-mbstring
    php-mcrypt
    php-curl
    php-intl
    php-xdebug
    php-xml
    php-mysql
    php-gd
    php-memcache
    redis-server
    memcached
    imagemagick
    nginx
    htop
    git-core
    zip
    unzip
    curl
    make
    gettext
    ntp
    postfix
    mysql-server
    ruby
    ruby-dev
    gcc
    samba
)

### FUNCTIONS

network_detection() {
  # Network Detection
  #
  # Make an HTTP request to google.com to determine if outside access is available
  # to us. If 3 attempts with a timeout of 5 seconds are not successful, then we'll
  # skip a few things further in provisioning rather than create a bunch of errors.
  if [[ "$(wget --tries=3 --timeout=5 --spider http://google.com 2>&1 | grep 'connected')" ]]; then
    echo "Network connection detected..."
    ping_result="Connected"
  else
    echo "Network connection not detected. Unable to reach google.com..."
    ping_result="Not Connected"
  fi
}

network_check() {
  network_detection
  if [[ ! "$ping_result" == "Connected" ]]; then
    echo -e "\nNo network connection available, skipping package installation"
    exit 0
  fi
}

noroot() {
  sudo -EH -u "ubuntu" "$@";
}

profile_setup() {
  # Copy custom dotfiles and bin file for the vagrant user from local
  cp "/srv/config/bash_profile" "/home/ubuntu/.bash_profile"
  cp "/srv/config/locale" "/etc/default/locale"

  if [[ ! -d "/home/ubuntu/bin" ]]; then
    mkdir "/home/ubuntu/bin"
  fi

  rsync -rvzh --delete "/srv/config/homebin/" "/home/vagrant/bin/"
  chmod +x /home/vagrant/bin/*

  echo " * Copied /srv/config/bash_profile                      to /home/ubuntu/.bash_profile"
  echo " * Copied /srv/config/locale                            to /etc/default/locale"
  echo " * rsync'd /srv/config/homebin                          to /home/ubuntu/bin"

  # If a bash_prompt file exists in the VVV config/ directory, copy to the VM.
  if [[ -f "/srv/config/bash_prompt" ]]; then
    cp "/srv/config/bash_prompt" "/home/ubuntu/.bash_prompt"
    echo " * Copied /srv/config/bash_prompt to /home/ubuntu/.bash_prompt"
  fi
}

package_check() {
  # Loop through each of our packages that should be installed on the system. If
  # not yet installed, it should be added to the array of packages to install.
  local pkg
  local package_version

  for pkg in "${apt_package_check_list[@]}"; do
    package_version=$(dpkg -s "${pkg}" 2>&1 | grep 'Version:' | cut -d " " -f 2)
    if [[ -n "${package_version}" ]]; then
      space_count="$(expr 20 - "${#pkg}")" #11
      pack_space_count="$(expr 30 - "${#package_version}")"
      real_space="$(expr ${space_count} + ${pack_space_count} + ${#package_version})"
      printf " * $pkg %${real_space}.${#package_version}s ${package_version}\n"
    else
      echo " *" $pkg [not installed]
      apt_package_install_list+=($pkg)
    fi
  done
}

package_install() {
  package_check

  # MySQL
  #
  # Use debconf-set-selections to specify the default password for the root MySQL
  # account. This runs on every provision, even if MySQL has been installed. If
  # MySQL is already installed, it will not affect anything.
  echo mysql-server mysql-server/root_password password "root" | debconf-set-selections
  echo mysql-server mysql-server/root_password_again password "root" | debconf-set-selections

  # Postfix
  #
  # Use debconf-set-selections to specify the selections in the postfix setup. Set
  # up as an 'Internet Site' with the host name 'spinebox'. Note that if your current
  # Internet connection does not allow communication over port 25, you will not be
  # able to send mail, even with postfix installed.
  echo postfix postfix/main_mailer_type select Internet Site | debconf-set-selections
  echo postfix postfix/mailname string spinebox | debconf-set-selections

  # Provide our custom apt sources before running `apt-get update`
  ln -sf /srv/config/apt-source-append.list /etc/apt/sources.list.d/spine-sources.list
  echo "Linked custom apt sources"

  # Retrieve the Nginx signing key from nginx.org
  echo "Applying Nginx signing key..."
  wget --quiet "http://nginx.org/keys/nginx_signing.key" -O- | apt-key add -

  # Apply the mongodb signing key
  echo "Applying MongoDB signing key..."
  apt-key adv --quiet --keyserver "hkp://keyserver.ubuntu.com:80" --recv-key D68FA50FEA312927 2>&1 | grep "gpg:"
  apt-key export D68FA50FEA312927 | apt-key add -

  # Apply RabbitMQ signing key
  # echo "Applying RabbitMQ signing key..."
  # wget --quiet "https://www.rabbitmq.com/rabbitmq-signing-key-public.asc" -O- | apt-key add -
  # apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 6B73A36E6026DFCA

  # Retrieve the Elasticsearch signing key
  # wget -qO - https://packages.elastic.co/GPG-KEY-elasticsearch | apt-key add -

  # Add Redis and PHP PPA
  add-apt-repository ppa:chris-lea/redis-server
  # LC_ALL=C.UTF-8 add-apt-repository ppa:ondrej/php

  # Update all of the package references before installing anything
  echo "Running apt-get update..."
  apt-get update -y

  # Install required packages
  echo "Installing apt-get packages..."
  apt-get install -y ${apt_package_install_list[@]}
  # Clean up apt caches
  apt-get clean
}

java_setup() {
  if [ -d "/opt/jre1.8.0_77" ]; then
    echo "Skipping Java setup"
    return;
  fi

  echo "Downloading Oracle Java..."
  wget -q -O jre-8u77-linux-x64.tar.gz https://www.dropbox.com/s/3csn0qyhmbtxqan/jre-8u77-linux-x64.tar.gz?dl=0

  echo "Installing Java..."
  tar -xzf jre-8u77-linux-x64.tar.gz

  mv jre1.8.0_77 /opt/

  if [ -L "/etc/alternatives/java" ]; then
    update-alternatives --remove-all "java"
  fi

  update-alternatives --install "/usr/bin/java" "java" "/opt/jre1.8.0_77/bin/java" 1

  echo "Java installed"
}

nginx_setup() {
  # Create an SSL key and certificate for HTTPS support.
  if [[ ! -e /etc/nginx/server.key ]]; then
    echo "Generate Nginx server private key..."
    spineboxrsa="$(openssl genrsa -out /etc/nginx/server.key 2048 2>&1)"
    echo "$spineboxrsa"
  fi
  if [[ ! -e /etc/nginx/server.crt ]]; then
    echo "Sign the certificate using the above private key..."
    spineboxcert="$(openssl req -new -x509 \
            -key /etc/nginx/server.key \
            -out /etc/nginx/server.crt \
            -days 3650 \
            -subj /CN=*.spinebox.local 2>&1)"
    echo "$spineboxcert"
  fi

  echo -e "\nSetup configuration files..."

  # Used to ensure proper services are started on `vagrant up`
  cp "/srv/config/init/start.conf" "/etc/init/start.conf"
  echo " * Copied /srv/config/init/start.conf               to /etc/init/start.conf"

  # Copy nginx configuration from local
  cp "/srv/config/nginx-config/nginx.conf" "/etc/nginx/nginx.conf"
  cp "/srv/config/nginx-config/fastcgi_params" "/etc/nginx/"
  cp "/srv/config/nginx-config/upstream.conf" "/etc/nginx/conf.d/"
  cp "/srv/config/nginx-config/options-ssl-nginx.conf" "/etc/nginx/conf.d/"

  if [[ ! -d "/etc/nginx/custom-sites" ]]; then
    mkdir "/etc/nginx/custom-sites/"
  fi
  rsync -rvzh --delete "/srv/config/nginx-config/sites/" "/etc/nginx/custom-sites/"
  rm -rf /etc/nginx/conf.d/default.conf
  echo " * Copied /srv/config/nginx-config/nginx.conf                           to /etc/nginx/nginx.conf"
  echo " * Rsync'd /srv/config/nginx-config/sites/                              to /etc/nginx/custom-sites"
  echo " * Rsync'd /srv/config/nginx-config/options-ssl-nginx.conf              to /etc/nginx/options-ssl-nginx.conf"

  # Add the vagrant user to the www-data group so that it has better access
  # to PHP and Nginx related files.
  usermod -a -G www-data ubuntu
}

phpfpm_setup() {
  # Copy php-fpm configuration from local
  cp "/srv/config/php7-fpm-config/php-fpm.conf" "/etc/php/7.0/fpm/php-fpm.conf"
  cp "/srv/config/php7-fpm-config/www.conf" "/etc/php/7.0/fpm/pool.d/www.conf"
  cp "/srv/config/php7-fpm-config/php-custom.ini" "/etc/php/7.0/fpm/conf.d/php-custom.ini"
  cp "/srv/config/php7-fpm-config/opcache.ini" "/etc/php/7.0/fpm/conf.d/opcache.ini"
  # cp "/srv/config/php7-fpm-config/xdebug.ini" "/etc/php/5.6/mods-available/xdebug.ini"

  # Find the path to Xdebug and prepend it to xdebug.ini
  # XDEBUG_PATH=$( find /usr -name 'xdebug.so' | head -1 )
  # sed -i "1izend_extension=\"$XDEBUG_PATH\"" "/etc/php/5.6/mods-available/xdebug.ini"

  echo " * Copied /srv/config/php7-fpm-config/php-fpm.conf      to /etc/php/7.0/fpm/php-fpm.conf"
  echo " * Copied /srv/config/php7-fpm-config/www.conf          to /etc/php/7.0/fpm/pool.d/www.conf"
  echo " * Copied /srv/config/php7-fpm-config/php-custom.ini    to /etc/php/7.0/fpm/conf.d/php-custom.ini"
  echo " * Copied /srv/config/php7-fpm-config/opcache.ini       to /etc/php/7.0/fpm/conf.d/opcache.ini"
  echo " * Copied /srv/config/php7-fpm-config/xdebug.ini        to /etc/php/7.0/mods-available/xdebug.ini"
}

redis_setup() {
  # Copy mysql configuration from local
  cp "/srv/config/redis-config/redis.conf" "/etc/redis/redis.conf"

  echo " * Copied /srv/config/redis-config/redis.conf      /etc/redis.conf"

  echo "service redis-server restart"
  service redis-server restart
}

ruby_setup() {
  gem install sass -v 3.4.22 --no-ri --no-rdoc
  gem install compass --no-ri --no-rdoc
}

nodejs_setup() {
  echo "Installing nodejs"
  curl -SLO "https://nodejs.org/dist/v$NODE_VERSION/node-v$NODE_VERSION-linux-x64.tar.gz" \
  && tar -xzf "node-v$NODE_VERSION-linux-x64.tar.gz" -C /usr/local --strip-components=1 \
  && ln -s /usr/local/bin/node /usr/local/bin/nodejs

  npm install --global bower uglify-js uglifycss
}

composer_setup() {
  php -r "copy('https://getcomposer.org/installer', 'composer-setup.php');" \
	&& php composer-setup.php --filename=composer --install-dir=/usr/bin \
	&& php -r "unlink('composer-setup.php');"
}

samba_setup() {
  if [[ ! -d "/var/www" ]]; then
    mkdir /var/www
    chown ubuntu:ubuntu /var/www
    chmod 775 /var/www
  fi

  echo "* Adding smbuser ubuntu with password ubuntu"
  (echo ubuntu; echo ubuntu) | smbpasswd -s -a ubuntu
  cp /srv/config/samba-config/smb.conf /etc/samba/
  echo "* Copied /srv/config/samba-config/smb.conf to /etc/samba/smb.conf"
}

# elasticsearch_setup() {
#   # Copy Config
#   cp "/srv/config/elasticsearch-config/elasticsearch.yml" "/etc/elasticsearch/elasticsearch.yml"
#   echo " * Copied /srv/config/elasticsearch-config/elasticsearch.yml    to /etc/elasticsearch/elasticsearch.yml"

#   cd /usr/share/elasticsearch

#   if [[ -d "/usr/share/elasticsearch/plugins/head" ]]; then
#       echo -e "\nSkip plugin head"
#   else
#       echo -e "\nInstalling plugin head"
#       bin/plugin install mobz/elasticsearch-head
#   fi

#   if [[ -d "/usr/share/elasticsearch/plugins/bundle" ]]; then
#       echo -e "\nSkip plugin bundle"
#   else
#     echo -e "\nInstalling plugin bundle"
#     bin/plugin install 'https://github.com/jprante/elasticsearch-plugin-bundle/releases/download/2.2.0.2/elasticsearch-plugin-bundle-2.2.0.2-plugin.zip'
#   fi

#   if [[ -d "/usr/share/elasticsearch/plugins/license" ]]; then
#       echo -e "\nSkip plugin license"
#   else
#       echo -e "\nInstalling plugin license"
#       bin/plugin install license
#   fi

#   if [[ -d "/usr/share/elasticsearch/plugins/marvel-agent" ]]; then
#       echo -e "\nSkip plugin marvel"
#   else
#       echo -e "\nInstalling plugin marvel"
#       echo "y" | bin/plugin install marvel-agent
#       /opt/kibana/bin/kibana plugin --install elasticsearch/marvel/latest
#   fi

#   cp "/srv/config/elasticsearch-config/kibana" "/etc/default/kibana"
#   echo " * Copied /srv/config/elasticsearch-config/kibana to /etc/default/kibana"

#   update-rc.d elasticsearch defaults 95 10
#   update-rc.d kibana defaults 95 10
#   service elasticsearch restart
#   service kibana restart
# }

mysql_setup() {
  # If MySQL is installed, go through the various imports and service tasks.
  local exists_mysql

  exists_mysql="$(service mysql status)"
  if [[ "mysql: unrecognized service" != "${exists_mysql}" ]]; then
    echo -e "\nSetup MySQL configuration file links..."

    # Copy mysql configuration from local
    cp "/srv/config/mysql-config/my.cnf" "/etc/mysql/my.cnf"
    cp "/srv/config/mysql-config/root-my.cnf" "/home/vagrant/.my.cnf"

    echo " * Copied /srv/config/mysql-config/my.cnf               to /etc/mysql/my.cnf"
    echo " * Copied /srv/config/mysql-config/root-my.cnf          to /home/vagrant/.my.cnf"

    # MySQL gives us an error if we restart a non running service, which
    # happens after a `vagrant halt`. Check to see if it's running before
    # deciding whether to start or restart.
    if [[ "mysql stop/waiting" == "${exists_mysql}" ]]; then
      echo "service mysql start"
      service mysql start
      else
      echo "service mysql restart"
      service mysql restart
    fi

    # IMPORT SQL
    #
    # Create the databases (unique to system) that will be imported with
    # the mysqldump files located in database/backups/
    if [[ -f "/srv/db-mysql/init-custom.sql" ]]; then
      mysql -u "root" -p"root" < "/srv/db-mysql/init-custom.sql"
      echo -e "\nInitial custom MySQL scripting..."
    else
      echo -e "\nNo custom MySQL scripting found in db-mysql/init-custom.sql, skipping..."
    fi

    # Setup MySQL by importing an init file that creates necessary
    # users and databases that our vagrant setup relies on.
    mysql -u "root" -p"root" < "/srv/db-mysql/init.sql"
    echo "Initial MySQL prep..."

    # Process each mysqldump SQL file in database/backups to import
    # an initial data set for MySQL.
    # "/home/vagrant/bin/db_import"
  else
    echo -e "\nMySQL is not installed. No databases imported."
  fi
}

# mongod_setup() {
#   # Copy mysql configuration from local
#   cp "/srv/config/mongod-config/mongod.conf" "/etc/mongod.conf"
#   cp "/srv/config/mongod-config/mongod.service" "/lib/systemd/system/mongod.service"
#   systemctl enable mongod
#   echo " * Copied /srv/config/mongod-config/mongod.conf      to /etc/mongod.conf"
#   echo " * Copied /srv/config/mongod-config/mongod.service   to /lib/systemd/system/mongod.service"

#   echo "service mongod restart"
#   service mongod restart
# }

tools_install() {
  pecl install xdebug
}

opcached_status(){
  # Checkout Opcache Status to provide a dashboard for viewing statistics
  # about PHP's built in opcache.
  if [[ ! -d "/srv/www/default/opcache-status" ]]; then
    echo -e "\nDownloading Opcache Status, see https://github.com/rlerdorf/opcache-status/"
    cd /srv/www/default
    git clone "https://github.com/rlerdorf/opcache-status.git" opcache-status
  else
    echo -e "\nUpdating Opcache Status"
    cd /srv/www/default/opcache-status
    git pull --rebase origin master
  fi
}

phpmyadmin_setup() {
  # Download phpMyAdmin
  if [[ ! -d /srv/www/default/database-admin ]]; then
    echo "Downloading phpMyAdmin..."
    cd /srv/www/default
    wget -q -O phpmyadmin.tar.gz "https://files.phpmyadmin.net/phpMyAdmin/4.4.10/phpMyAdmin-4.4.10-all-languages.tar.gz"
    tar -xf phpmyadmin.tar.gz
    mv phpMyAdmin-4.4.10-all-languages database-admin
    rm phpmyadmin.tar.gz
  else
    echo "PHPMyAdmin already installed."
  fi
  cp "/srv/config/phpmyadmin-config/config.inc.php" "/srv/www/default/database-admin/"
}

services_restart() {
  # RESTART SERVICES
  #
  # Make sure the services we expect to be running are running.
  echo -e "\nRestart services..."
  service nginx restart

  # Disable PHP Xdebug module by default
  # php5dismod xdebug

  # Enable PHP mcrypt module by default
  # php5enmod mcrypt

  service php7.0-fpm restart
  service smbd restart

  # Restart Rabbit MQ
  # service rabbitmq-server restart

  # Restart vsftpd
  # service vsftpd restart
}

# rabbitmq_setup() {
#   # Enable Plugins
#   echo -e "\nEnable RabbitMQ Plugins"
#   rabbitmq-plugins enable rabbitmq_management
#   echo -e "\nPlugin rabbitmq_management enabled"

#   # Add User
#   rabbitmqctl add_user vagrant vagrant
#   echo -e "\nUser vagrant with password vagrant created"

#   # Set permission
#   rabbitmqctl set_user_tags vagrant administrator
#   echo -e "\nUser promoted"
# }

htop_setup() {
    if [[ ! -d "/home/vagrant/.config/htop" ]]; then
        mkdir -p /home/vagrant/.config/htop
        echo -e "\nCreated htop config directory"
    fi
    cp "/srv/config/htop-config/htoprc" "/home/vagrant/.config/htop/htoprc"
    echo " * Copied /srv/config/htop-config/htoprc      to /home/vagrant/.config/htop/htoprc"
}

vsftpd_setup() {
  cp "/srv/config/vsftpd-config/vsftpd.conf" "/etc/vsftpd.conf"
  echo -e " * Copied /srv/config/vsftpd-config/vsftpd.conf    to /etc/vsftpd.conf"
}


# SCRIPT

network_check
# Profile_setup
echo "Bash profile setup and directories."
profile_setup

network_check
# Package and Tools Install
echo " "
echo "Main packages check and install."
package_install
# java_setup
htop_setup
# tools_install
nginx_setup
phpfpm_setup
mysql_setup
# mongod_setup
redis_setup
ruby_setup
nodejs_setup
nginx_setup
composer_setup
samba_setup
# elasticsearch_setup
# rabbitmq_setup
# vsftpd_setup
services_restart

echo " "
echo "Installing/updating debugging tools"
opcached_status
phpmyadmin_setup

# And it's done
end_seconds="$(date +%s)"
echo "-----------------------------"
echo "Provisioning complete in "$((${end_seconds} - ${start_seconds}))" seconds"
echo "For further setup instructions, visit https://github.com/createproblem/vagrant-spine"

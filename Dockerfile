FROM phusion/baseimage

# Set environment variables
ENV DEBIAN_FRONTEND noninteractive
ENV HOME="/root"
ENV TERM=xterm
ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8
ENV ASTERISKUSER asterisk
ENV ASTERISK_DB_PW 59MNtQNncbIsw
ENV AMPMGRPASS 47lcJkDYxEZG1rkzPt85OqrZoYsMYnZi
ENV ASTERISKVER 13
ENV FREEPBXVER 13.0


EXPOSE 80 5060

CMD ["/sbin/my_init"]

# Setup services
COPY start-apache2.sh /etc/service/apache2/run
COPY start-mysqld.sh /etc/service/mysqld/run
COPY start-asterisk.sh /etc/service/asterisk/run
COPY start-amportal.sh /etc/my_init.d/10_amportal.sh
COPY start-fail2ban.sh /etc/my_init.d/20_fail2ban.sh

RUN chmod +x /etc/service/apache2/run && \
    chmod +x /etc/service/mysqld/run && \
    chmod +x /etc/service/asterisk/run && \
    chmod +x /etc/my_init.d/10_amportal.sh && \
    chmod +x /etc/my_init.d/20_fail2ban.sh

# Following steps on FreePBX wiki
# http://wiki.freepbx.org/display/HTGS/Installing+FreePBX+12+on+Ubuntu+Server+14.04+LTS

# Install Required Dependencies
RUN sed -i 's/archive.ubuntu.com/bouyguestelecom.ubuntu.lafibre.info/' /etc/apt/sources.list && \
    apt-get update && \
    apt-get upgrade -y && \
    apt-get install -y \
        apache2 \
        curl \
        fail2ban \
        mpg123 \
        mysql-client \
        mysql-server \
        php7.0 \
        php7.0-cli \
        php7.0-curl \
        php-db \
        php7.0-gd \
        php7.0-mysql \
        php-pear \
        sox\
        sqlite3 \
        unixodbc\
        uuid \
        asterisk asterisk-mysql asterisk-mp3 && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* && \
    mv /etc/fail2ban/filter.d/asterisk.conf /etc/fail2ban/filter.d/asterisk.conf.org && \
    mv /etc/fail2ban/jail.conf /etc/fail2ban/jail.conf.org

# Copy new fail2ban config for asterisk 13
COPY conf/fail2ban/asterisk.conf /etc/fail2ban/filter.d/asterisk.conf
COPY conf/fail2ban/jail.conf /etc/fail2ban/jail.conf

# Replace default conf files to reduce memory usage
# COPY conf/my-small.cnf /etc/mysql/my.cnf
# COPY conf/mpm_prefork.conf /etc/apache2/mods-available/mpm_prefork.conf
COPY conf/fpbx-manager.conf /etc/asterisk/manager.d/freepbx.conf

# Install Pear requirements
RUN pear uninstall db && \
    pear install db-1.7.14

# Add Asterisk user
RUN chown -R $ASTERISKUSER. /etc/asterisk && \
    chown -R $ASTERISKUSER. /var/lib/asterisk && \
    chown -R $ASTERISKUSER. /var/log/asterisk && \
    chown -R $ASTERISKUSER. /var/spool/asterisk && \
    chown -R $ASTERISKUSER. /usr/lib/asterisk && \
    chown -R $ASTERISKUSER. /var/www/ && \
    chown -R $ASTERISKUSER. /var/www/* && \
    rm -rf /var/www/html

# Configure apache
RUN sed -i 's/\(^upload_max_filesize = \).*/\120M/' /etc/php/7.0/fpm/php.ini && \
    cp /etc/apache2/apache2.conf /etc/apache2/apache2.conf_orig && \
    sed -i 's/^\(User\|Group\).*/\1 asterisk/' /etc/apache2/apache2.conf && \
    sed -i 's/AllowOverride None/AllowOverride All/' /etc/apache2/apache2.conf && \
    a2enmod rewrite

# Configure Asterisk database in MYSQL
RUN /etc/init.d/mysql start && \
    mysqladmin -u root create asterisk && \
    mysqladmin -u root create asteriskcdrdb && \
    mysql -u root -e "GRANT ALL PRIVILEGES ON asterisk.* TO $ASTERISKUSER@localhost IDENTIFIED BY '$ASTERISK_DB_PW';" && \
    mysql -u root -e "GRANT ALL PRIVILEGES ON asteriskcdrdb.* TO $ASTERISKUSER@localhost IDENTIFIED BY '$ASTERISK_DB_PW';" && \
    mysql -u root -e "flush privileges;"
    

# Download and install FreePBX
WORKDIR /usr/src
RUN curl -sf -o freepbx-$FREEPBXVER.tgz -L http://mirror.freepbx.org/modules/packages/freepbx/freepbx-$FREEPBXVER-latest.tgz && \
    tar xfz freepbx-$FREEPBXVER.tgz && \
    rm freepbx-$FREEPBXVER.tgz && \
    cd /usr/src/freepbx && \
    /etc/init.d/mysql start && \
    /etc/init.d/apache2 start && \
    sed -i '1 s/^.*$/[directories]/g' /etc/asterisk/asterisk.conf && \
    echo "noload => res_pjsip.so" >> /etc/asterisk/modules.conf && \
    sed -i "s/AMPMGRPASS/$AMPMGRPASS/" /etc/asterisk/manager.d/freepbx.conf && \
    ./start_asterisk start && \
    ./install -n --ampcgibin /usr/lib/cgi-bin --dbuser=$ASTERISKUSER --dbpass=$ASTERISK_DB_PW && \
    ln -sf /var/www/html/admin/modules/core/etc/* /etc/asterisk/ && \
    /etc/init.d/asterisk reload && \
    mysql -u$ASTERISKUSER -p$ASTERISK_DB_PW asterisk -e "INSERT into logfile_logfiles \
        (name, debug, dtmf, error, fax, notice, verbose, warning, security) \
        VALUES ('fail2ban', 'off', 'off', 'on', 'off', 'on', 'off', 'on', 'on');" && \
    ln -s /var/lib/asterisk/moh /var/lib/asterisk/mohmp3 && \
    rm -f /usr/share/asterisk/sounds/custom && \
    rm -rf /usr/share/asterisk/sounds/en* && \
    ln -s /var/lib/asterisk/sounds/custom /usr/share/asterisk/sounds/custom && \
    ln -s /var/lib/asterisk/sounds/{en,fr} /usr/share/asterisk/sounds/ && \
    rm -rf /usr/src/freepbx

#Make CDRs work
COPY conf/cdr/odbcinst.ini /etc/odbcinst.ini

WORKDIR /

#!/bin/bash

# What it does:
#	gets a domain/sub-domain name from a service
#	creates apache config file for http and https
#	Writes contents of config files accordingly
#	Enables the site
#	Creates SSL certificate for the site using letsencrypt
#	Informs the status to a service
#	restart apache2 service

NOW=$(date +"%d%m%Y_%H%M%S_%N")
LOG_PATH="/home/ssl_configurator_log"
LOGFILE="$LOG_PATH/$NOW.log"

#redirect stdout/stderr to a file
exec >> $LOGFILE 2>&1

echo "########################### START: $(date '+%d/%m/%Y %H:%M:%S') ###########################"

SERVICE_DOMAIN="https://myservice.mydomain.com"
DATA_URL="$SERVICE_DOMAIN/api/data-for-proxy-server/"
NOTIFY_URL="$SERVICE_DOMAIN/api/notify-ssl-setup-info/"
site_conf_file_location="/etc/apache2/sites-available"

HTTP_RESPONSE=$(curl --silent --write-out "HTTPSTATUS:%{http_code}" -X GET $DATA_URL)

# extract the body
HTTP_BODY=$(echo $HTTP_RESPONSE | sed -e 's/HTTPSTATUS\:.*//g')

# extract the status
HTTP_STATUS=$(echo $HTTP_RESPONSE | tr -d '\n' | sed -e 's/.*HTTPSTATUS://')

if [ $HTTP_STATUS -eq 200  ]; then
        #echo "$HTTP_BODY"
        restart_apache=false
        domains=""

        echo
        #for domain in $("E:\\jq" '.[]' <<< "$HTTP_BODY");               # for windows
        for domain in $(jq '.[]' <<< $HTTP_BODY);                        # for linux where jq is installed globally
                do
                        servn="${domain//\"}"                           # removing extra double-quotes
                        #echo $servn

                        if [ "$domains" != "" ]; then
                                domains+=","
                        fi

                        domains+=$servn

                        cname="www"
                        alias=$cname.$servn
                        #echo $alias

                        if [ ! -e "$site_conf_file_location/$servn-le-ssl.conf" ]
                                then
                                        echo "Going to prepare config for $servn"
                                        restart_apache=true
                                        #echo "$site_conf_file_location/$servn-le-ssl.conf NOT FOUND"
                                        #------------------------Creating http config for the site--------------------------------
echo "#### $cname $servn
<VirtualHost *:80>
        ServerName $servn
        ServerAlias $alias
        RewriteEngine  on
        ProxyPreserveHost On
        SSLProxyEngine on
        SSLProxyVerify none
        SSLProxyCheckPeerCN off
        SSLProxyCheckPeerName off
        SSLProxyCheckPeerExpire off


        RewriteCond %{REQUEST_METHOD} !^(GET)
        RewriteRule .* - [R=405,L]

        RewriteRule \"^/([A-Za-z0-9]{21,500})$\" \"https://mywebapp.mydomain.com/#/error/404\" [NE,L]
        RewriteRule \"^/l/([A-Za-z0-9]{21,500})$\" \"https://mywebapp.mydomain.com/#/error/404\" [NE,L]


        RewriteRule \"^\" \"https://www.mydomain.com/\" [L]
        LogLevel warn
        ErrorLog  /var/log/apache2/error.log
        CustomLog /var/log/apache2/access.log combined

        RewriteCond %{SERVER_NAME} =$alias [OR]
        RewriteCond %{SERVER_NAME} =$servn
        RewriteRule ^ https://%{SERVER_NAME}%{REQUEST_URI} [END,NE,R=permanent]
</VirtualHost>" > $site_conf_file_location/$servn.conf

                                        if ! echo -e $site_conf_file_location/$servn.conf; then
                                                echo "Virtual host wasn't created !"
                                        else
                                                echo "Virtual host created !"

                                                echo "Going to enable $servn"
                                                /usr/sbin/a2ensite $servn
                                        fi
                                        #====================================== end ===============================================

                                        #------------------------ creating https config for the site -----------------------------
                                        echo "Before creating letsencrypt cert, lets make clean directories first for $servn"
                                        rm -fr "/etc/letsencrypt/live/$servn"
                                        rm -fr "/etc/letsencrypt/archive/$servn"
                                        rm -f "/etc/letsencrypt/renewal/$servn.conf"

                                        echo "Going to create cert using letsencrypt"
                                        if certbot --apache -d $servn -m my@email.com --agree-tos -n; then
                                                echo "Successfully generated certificates for $servn"
                                        else
                                                echo "Failed to generate certificates $servn"
                                                echo "Going to disable site $servn"
                                                /usr/sbin/a2dissite $servn
                                                rm $site_conf_file_location/$servn.conf

                                                echo "Going to inform server about this failure"

                                                notify_full_url="$NOTIFY_URL?domain=$servn&isSuccess=false&msg=failed_to_generate_letsencrypt_certs"
                                                HTTP_RESPONSE=$(curl --silent --write-out "HTTPSTATUS:%{http_code}" -X GET $notify_full_url)

                                                # extract the status
                                                HTTP_STATUS=$(echo $HTTP_RESPONSE | tr -d '\n' | sed -e 's/.*HTTPSTATUS://')

                                                if [ $HTTP_STATUS -eq 200  ]; then
                                                        echo "Successfully informed that the ssl setup failed for $servn"
                                                else
                                                        echo "Failed to inform that the ssl setup failed for $servn"
                                                fi

                                                continue
                                        fi


echo "#### $cname $servn
<IfModule mod_ssl.c>
<VirtualHost *:443>
        ServerName $servn
        ServerAlias $alias

        RewriteEngine  on
        ProxyPreserveHost On
        SSLProxyEngine on
        SSLProxyVerify none
        SSLProxyCheckPeerCN off
        SSLProxyCheckPeerName off
        SSLProxyCheckPeerExpire off


        RewriteCond %{REQUEST_METHOD} !^(GET)
        RewriteRule .* - [R=405,L]

        RewriteRule \"^/([A-Za-z0-9]{21,500})$\" \"https://mywebapp.mydomain.com/#/error/404\" [NE,L]
        RewriteRule \"^/l/([A-Za-z0-9]{21,500})$\" \"https://mywebapp.mydomain.com/#/error/404\" [NE,L]

        RewriteRule \"^\" \"https://www.mydomain.com/\" [L]
                
        LogLevel warn
        ErrorLog  /var/log/apache2/error.log
        CustomLog /var/log/apache2/access.log combined

        SSLCertificateFile /etc/letsencrypt/live/$servn/fullchain.pem
        SSLCertificateKeyFile /etc/letsencrypt/live/$servn/privkey.pem
        Include /etc/letsencrypt/options-ssl-apache.conf
</VirtualHost>
</IfModule>" > $site_conf_file_location/$servn-le-ssl.conf

                                        if ! echo -e $site_conf_file_location/$servn-le-ssl.conf; then
                                                echo "Virtual host for ssl wasn't created !"
                                        else
                                                echo "Virtual host for ssl created !"

                                                echo "Going to inform server about this failure"

                                                notify_full_url="$NOTIFY_URL?domain=$servn&isSuccess=true&msg='generated_all_files_successfully'"

                                                HTTP_RESPONSE=$(curl --silent --write-out "HTTPSTATUS:%{http_code}" -X GET $notify_full_url)
                                                HTTP_STATUS=$(echo $HTTP_RESPONSE | tr -d '\n' | sed -e 's/.*HTTPSTATUS://')

                                                if [ $HTTP_STATUS -eq 200  ]; then
                                                        echo "Successfully informed that the ssl setup was created for $servn"
                                                else
                                                        echo "Failed to inform that the ssl setup was created for $servn"
                                                fi
                                        fi
                                        #====================================== end ==============================================
                        fi
                done
        if [ $restart_apache == true ]; then
                echo "going to restart apache server"
                echo 
                #service apache2 restart
                systemctl restart apache2
                if systemctl status apache2 --no-pager; then
                        echo "Everything was fine"
                else
                        echo "RED ALERT!! Apache server is down!"
                        notify_full_url="$NOTIFY_URL?domain=$domains&isSuccess=false&msg=apache_server_failed_to_start"

                        HTTP_RESPONSE=$(curl --silent --write-out "HTTPSTATUS:%{http_code}" -X GET $notify_full_url)
                        HTTP_STATUS=$(echo $HTTP_RESPONSE | tr -d '\n' | sed -e 's/.*HTTPSTATUS://')

                        if [ $HTTP_STATUS -eq 200  ]; then
                                echo "Successfully informed that the apache server failed to start"
                        else
                                echo "Failed to inform that the apache server could not start"
                        fi
                fi

        fi

        echo "########################### END: $(date '+%d/%m/%Y %H:%M:%S') ###########################"
        exit 1
else
        echo "$HTTP_BODY"
        echo "Error [HTTP status: $HTTP_STATUS]"
        echo "########################### END: $(date '+%d/%m/%Y %H:%M:%S') ###########################"
        exit 1
fi

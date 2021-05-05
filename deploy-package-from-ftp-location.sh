#!/bin/bash
#########################################
#                                       #
#    Deploy package from ftp directory  #
#                                       #
#########################################

redirect stdout/stderr to a file
exec >> deployment.log 2>&1

echo "#######################################################"
echo "START: $(date)"

sendgrid_api_key="API_KEY"
exception_middleware_email_password="PASSWORD"

hosting_server_ip="xx.xx.xxx.xxx"
database_name="database_name"
db_username="database_username"
db_password="database_password"

package_ftp_location=/home/agentftp/ftp/packages/backend
destination_directory=/var/www/sample_app/webservice
package_name=Sample.Build.Packagee.zip
package_folder_name=Sample.Build.Packagee
backup_directory=/home/agentftp/ftp/old_packages
systemd_service_name=dev-sample-app.service

while :
do
	sleep 300
	if [[ -f $package_ftp_location/$package_name ]]
	then
		echo "new build found..."
		echo $(date +%Y/%m/%d-%H:%M:%S)
		
		echo "Going stop systemd service"
		echo 
		systemctl stop $systemd_service_name
		systemctl status $systemd_service_name

		rm -fr $destination_directory/*
		echo "Deleted old content..."

		cp $package_ftp_location/$package_name $destination_directory/
		echo "coppied build to destination folder..."

		cd $destination_directory
		echo "changing directory to destination folder...."

		unzip $package_name
		echo "unzipped build..."

		mv $package_folder_name/WebService/* .

		rm $package_name
		echo "removed coppied zip build..."

		rm -fr $package_folder_name
		echo "removed extracted empty folder..."
		
		echo "Going to update appsettings file"
		echo
		sed -i "s/Host=127.0.0.1/Host=\"$hosting_server_ip\"/g" appsettings.json 
		sed -i "s/Username=DBUsername/Username=\"$db_username\"/g" appsettings.json
		sed -i "s/Password=DBPassword/Password=\"$db_password\"/g" appsettings.json
		sed -i "s/Database=DBName/Database=\"$database_name\"/g" appsettings.json
		sed -i "s/\"SendGridApiKey\": \"SENDGRID_API_KEY\"/\"SendGridApiKey\": \"$sendgrid_api_key\"/g" appsettings.json
		sed -i "s/\"Password\": \"EXCEPTION_EMAIL_PASSWORD\"/\"Password\": \"$exception_middleware_email_password\"/g" appsettings.json
		echo "updated appsettings"
		echo

		echo "Going to start systemd service"
		echo 
		systemctl start $systemd_service_name
		systemctl status $systemd_service_name
		
		echo "Going to restart apache2"
		echo
		service apache2 restart

		echo "Going to create backup"
		echo
		mv $package_ftp_location/$package_name $backup_directory/$package_folder_name.$(date +%Y%m%d%H%M%S).zip
		echo "created backup"

		echo "DONE!!"
	fi
done

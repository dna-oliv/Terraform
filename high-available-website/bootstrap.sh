#!/bin/bash
echo "Installing software"
yum update
yum install -y httpd
sudo amazon-linux-extras install php7.4

echo "<html>Healthy</html>" >> /var/www/html/healthy.html

service httpd start

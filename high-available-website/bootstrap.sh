#!/bin/bash
echo "Installing software"
yum update
yum install -y httpd24
yum install -y php73
yum install -y mysqlnd

echo "<html>Healthy</html>" >> /var/www/html/healthy.html

service httpd start

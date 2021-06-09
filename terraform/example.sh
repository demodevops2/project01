#!/bin/bash

sudo apt-get update
sudo apt-get install apache2 -y 
sudo echo "Webapp deployed in autoscaling group" > /var/www/html/index.html
sudo systemctl restart apache2

#!/bin/bash
# Define log file
LOG_FILE="/var/log/tomcat_installation.log"

MAJOR_VERSION=11
TOMCAT_VERSION=11.0.0-M22

# Function to log messages with timestamps
log() {
    echo "$(date +'%Y-%m-%d %H:%M:%S') - $1" | tee -a $LOG_FILE
}

# Start logging
log "Starting Tomcat installation script..."

set -e  # Exit immediately if a command exits with a non-zero status

# Check if Tomcat is already installed
if [ -d "/opt/apache-tomcat-$TOMCAT_VERSION" ]; then
    log "Tomcat version $TOMCAT_VERSION is already installed."
    exit 0
fi

# Download and install Java 17 and java 11
amazon-linux-extras install java-openjdk11 -y
log "Downloading and installing Java 17..."
wget https://download.java.net/java/GA/jdk17.0.2/dfd4a8d0985749f896bed50d7138ee7f/8/GPL/openjdk-17.0.2_linux-x64_bin.tar.gz
tar xvf openjdk-17.0.2_linux-x64_bin.tar.gz
sudo mv jdk-17.0.2/ /opt/jdk-17
sudo tee /etc/profile.d/jdk.sh <<EOF
export JAVA_HOME=/opt/jdk-17
export PATH=\$PATH:\$JAVA_HOME/bin
EOF

# Source the profile script to set JAVA_HOME
source /etc/profile.d/jdk.sh

# Construct the download URL for Tomcat
TOMCAT_URL="https://dlcdn.apache.org/tomcat/tomcat-$MAJOR_VERSION/v$TOMCAT_VERSION/bin/apache-tomcat-$TOMCAT_VERSION.tar.gz"

log "Fetching Tomcat version $TOMCAT_VERSION from $TOMCAT_URL"

# Download and extract Tomcat
log "Downloading Tomcat..."
wget $TOMCAT_URL
tar -zxvf apache-tomcat-$TOMCAT_VERSION.tar.gz

# Move Tomcat to /opt and set permissions
log "Moving Tomcat to /opt and setting permissions..."
sudo mv apache-tomcat-$TOMCAT_VERSION /opt/
sudo chown -R $(whoami):$(whoami) /opt/apache-tomcat-$TOMCAT_VERSION

# Prompt for Tomcat user password
read -sp "Enter password for Tomcat user: " password
echo

# Configure Tomcat users
TOMCAT_USER_CONFIG="/opt/apache-tomcat-$TOMCAT_VERSION/conf/tomcat-users.xml"
log "Configuring Tomcat users..."
sudo sed -i '56  a\<role rolename="manager-gui"/>' $TOMCAT_USER_CONFIG
sudo sed -i '57  a\<role rolename="manager-script"/>' $TOMCAT_USER_CONFIG
sudo sed -i '58  a\<user username="apachetomcat" password="'"$password"'" roles="manager-gui,manager-script"/>' $TOMCAT_USER_CONFIG
sudo sed -i '59  a\</tomcat-users>' $TOMCAT_USER_CONFIG
sudo sed -i '56d' $TOMCAT_USER_CONFIG
sudo sed -i '21d' /opt/apache-tomcat-$TOMCAT_VERSION/webapps/manager/META-INF/context.xml
sudo sed -i '22d' /opt/apache-tomcat-$TOMCAT_VERSION/webapps/manager/META-INF/context.xml

# Start Tomcat
log "Starting Tomcat..."
/opt/apache-tomcat-$TOMCAT_VERSION/bin/startup.sh

# Save Tomcat credentials
log "Saving Tomcat credentials..."
echo "username: apachetomcat" > tomcatcreds.txt
echo "password: $password" >> tomcatcreds.txt

# Clean up
log "Cleaning up..."
rm -f openjdk-17.0.2_linux-x64_bin.tar.gz
rm -f apache-tomcat-$TOMCAT_VERSION.tar.gz

log "Tomcat installation and configuration complete."
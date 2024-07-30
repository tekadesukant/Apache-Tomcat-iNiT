#!/bin/bash
# Define log file
LOG_FILE="/var/log/tomcat_installation.log"

# Fetched latest version 
TOMCAT_VERSION=11.0.0-M22
# Previous Versions : 9.0.91, 10.1.26

MAJOR_VERSION=$(echo "$TOMCAT_VERSION" | cut -d'.' -f1)

# Function to log messages with timestamps
log() {
    echo "$(date +'%Y-%m-%d %H:%M:%S') - $1" | tee -a $LOG_FILE
}

# Start logging
log "Starting Tomcat installation script..."

set -e  # Exit immediately if a command exits with a non-zero status

# Detect the operating system
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
elif [ -f /etc/redhat-release ]; then
    OS="centos"
else
    log "Unsupported OS"
    exit 1
fi

# Common installation steps
log "Downloading Tomcat..."
TOMCAT_URL="https://dlcdn.apache.org/tomcat/tomcat-$MAJOR_VERSION/v$TOMCAT_VERSION/bin/apache-tomcat-$TOMCAT_VERSION.tar.gz"
wget $TOMCAT_URL

sudo tee /opt/portuner.sh <<'EOF'
#!/bin/bash
# TESTED SUCCESFULLY FOR UBUNTU INSTANCE
# Prompt the user to enter a new port number
echo "Enter new port number (1024-65535): "
read CUSTOM_TOMCAT_PORT

# Update the port number in server.xml
sudo sed -i 's/port="8080"/port="'"$CUSTOM_TOMCAT_PORT"'"/' /opt/tomcat/conf/server.xml

# Update the portnumber in tomcatcreds.txt
sudo sed -i '4 c portnumber="'"$CUSTOM_TOMCAT_PORT"'"' /opt/tomcatcreds.txt

echo "Port number successfully updated to "'"$CUSTOM_TOMCAT_PORT"'". "

# Optionally, check Tomcat service status
if systemctl is-active --quiet tomcat; then
    echo "Tomcat is currently running. Please restart Tomcat (comm: tomcat -restart) to apply changes."
else
    echo "Tomcat is not running. You can start Tomcat (comm: tomcat -start) to apply the new port number."
fi
EOF

sudo chmod +x /opt/portuner.sh

sudo tee /opt/passwd.sh <<'EOF'
#!/bin/bash

# Prompt the user to enter a new password
echo "Enter new Tomcat manager password (minimum 6 characters): "
read CUSTOM_TOMCAT_PASSWD

# Update the password in tomcat-users.xml
sudo sed -i '58  c <user username="apachetomcat" password="'"$CUSTOM_TOMCAT_PASSWD"'" roles="manager-gui,manager-script"/>' /opt/tomcat/conf/tomcat-users.xml

# Update the password in tomcatcreds.txt
sudo sed -i '2 c password="'"$CUSTOM_TOMCAT_PASSWD"'"' /opt/tomcatcreds.txt

echo "Password successfully updated."

# Optionally restart Tomcat to apply the new password
sudo tomcat -restart
EOF

sudo chmod +x /opt/passwd.sh

sudo tee /opt/remove.sh <<'EOF'
#!/bin/bash
sudo /opt/tomcat/bin/shutdown.sh
sleep 10
sudo rm -r /opt/tomcat/
sudo rm -r /usr/local/sbin/tomcat
sudo rm -f /opt/tomcatcreds.txt
echo "Tomcat removed successfully"
EOF

sudo chmod +x /opt/remove.sh

tar -zxvf apache-tomcat-$TOMCAT_VERSION.tar.gz
mv apache-tomcat-$TOMCAT_VERSION tomcat

# Move Tomcat to /opt and set permissions
log "Moving Tomcat to /opt and setting permissions..."
sudo mv tomcat /opt/
sudo chown -R $USER:$USER /opt/tomcat

password=tomcat123

# Configure Tomcat users
TOMCAT_USER_CONFIG="/opt/tomcat/conf/tomcat-users.xml"
log "Configuring Tomcat users..."
sudo sed -i '56  a\<role rolename="manager-gui"/>' $TOMCAT_USER_CONFIG
sudo sed -i '57  a\<role rolename="manager-script"/>' $TOMCAT_USER_CONFIG
sudo sed -i '58  a\<user username="apachetomcat" password="'"$password"'" roles="manager-gui,manager-script"/>' $TOMCAT_USER_CONFIG
sudo sed -i '59  a\</tomcat-users>' $TOMCAT_USER_CONFIG
sudo sed -i '56d' $TOMCAT_USER_CONFIG
sudo sed -i '21d' /opt/tomcat/webapps/manager/META-INF/context.xml
sudo sed -i '22d' /opt/tomcat/webapps/manager/META-INF/context.xml

# Create the tomcat script
sudo tee /usr/local/sbin/tomcat << 'EOF'
#!/bin/bash

case "$1" in
    --up)
        echo "Starting Tomcat..."
        sudo -u root /opt/tomcat/bin/startup.sh
        ;;
    --down)
        echo "Stopping Tomcat..."
        sudo -u root /opt/tomcat/bin/shutdown.sh
        ;;
    --restart)
        echo "Restarting Tomcat..."
        echo "Stopping Tomcat..."
        sudo -u root /opt/tomcat/bin/shutdown.sh
        sleep 5  # Wait for Tomcat to stop completely
        echo "Starting Tomcat..."
        sudo -u root /opt/tomcat/bin/startup.sh
        ;;
    --delete)
        echo "Removing Tomcat..."
        sudo -u root /opt/remove.sh
        ;;
    --port-change)
        sudo -u root /opt/portuner.sh
        ;;
    --passwd-change)
        sudo -u root /opt/passwd.sh
        ;;
    *)
        echo "Usage: tomcat {--up|--down|--restart|--delete|--port-change|--passwd-change}"
        ;;
esac
EOF

sudo chmod +x /usr/local/sbin/tomcat

# Add an alias to the .bashrc file
echo "alias tomcat='/usr/local/sbin/tomcat'" >> ~/.bashrc

# System-specific steps
if [ "$OS" = "amazon" ]; then
    log "Amazon Linux detected. Installing Java 17..."
    amazon-linux-extras install java-openjdk11 -y
    wget https://download.java.net/java/GA/jdk17.0.2/dfd4a8d0985749f896bed50d7138ee7f/8/GPL/openjdk-17.0.2_linux-x64_bin.tar.gz
    tar xvf openjdk-17.0.2_linux-x64_bin.tar.gz
    sudo mv jdk-17.0.2/ /opt/jdk-17
    sudo tee /etc/profile.d/jdk.sh <<EOF
    export JAVA_HOME=/opt/jdk-17
    export PATH=\$PATH:\$JAVA_HOME/bin
EOF

# Source the profile script to set JAVA_HOME
source /etc/profile.d/jdk.sh
    log "Java 17 installed."
elif [ "$OS" = "ubuntu" ]; then
    log "Ubuntu detected. Updating package lists and installing Java 17..."
    log "Updating package lists..."
    sudo apt update
    sudo apt-get update
    log "Installing Java development kit..."
    sudo add-apt-repository ppa:openjdk-r/ppa
    sudo apt install openjdk-11-jdk -y
    sudo apt install openjdk-17-jdk -y
    log "Java installed."
else
    log "Unsupported OS detected. Cannot proceed with the installation."
    exit 1
fi

# Verify Java installation
java -version

# Start Tomcat
log "Starting Tomcat..."
/opt/tomcat/bin/startup.sh

# Save Tomcat credentials
log "Saving Tomcat credentials..."
echo "username: apachetomcat" > /opt/tomcatcreds.txt
echo "password: $password" >> /opt/tomcatcreds.txt
echo "tomcat path: /opt/tomcat" >> /opt/tomcatcreds.txt
echo "port number:"8080"" >> /opt/tomcatcreds.txt
echo "COMM TO RUN TOMCAT:sudo tomcat -up" >> /opt/tomcatcreds.txt 
echo "COMM TO STOP TOMCAT:sudo tomcat -down" >> /opt/tomcatcreds.txt 
echo "COMM TO RESTART TOMCAT:sudo tomcat -restart" >> /opt/tomcatcreds.txt 
echo "COMM TO REMOVE TOMCAT:sudo tomcat -remove" >> /opt/tomcatcreds.txt 
echo "COMM TO CHANGE PASSWORD TOMCAT:sudo tomcat -passwd" >> /opt/tomcatcreds.txt
echo "COMM TO CHANGE PORT NUMBER TOMCAT:sudo tomcat -portuner" >> /opt/tomcatcreds.txt 

# Clean up
log "Cleaning up..."
rm -f apache-tomcat-$TOMCAT_VERSION.tar.gz

# Reload the .bashrc file
log "Reloading .bashrc..."
log "Tomcat installation and configuration complete."
exec bash 
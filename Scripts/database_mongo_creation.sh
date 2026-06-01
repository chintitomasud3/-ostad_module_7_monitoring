
#!/bin/bash

set -e  # error hole script stop korbe

echo "🔄 Updating system..."
sudo apt-get update

echo "📦 Adding MongoDB repo..."
echo "deb [ arch=amd64,arm64 signed-by=/usr/share/keyrings/mongodb-server-7.0.gpg ] https://repo.mongodb.org/apt/ubuntu jammy/mongodb-org/7.0 multiverse" | \
sudo tee /etc/apt/sources.list.d/mongodb-org-7.0.list

echo "🔑 Fixing GPG key..."
sudo rm -f /usr/share/keyrings/mongodb-server-7.0.gpg
curl -fsSL https://pgp.mongodb.com/server-7.0.asc | \
sudo gpg --dearmor -o /usr/share/keyrings/mongodb-server-7.0.gpg

echo "🔄 Updating package list again..."
sudo apt update

echo "⬆️ Upgrading system..."
sudo apt-get upgrade -y

echo "📥 Installing MongoDB..."
sudo apt install -y mongodb-org

echo "🚀 Starting MongoDB..."
sudo systemctl start mongod

echo "✅ Enabling MongoDB on boot..."
sudo systemctl enable mongod

echo "📊 Checking MongoDB status..."
sudo systemctl status mongod --no-pager

echo "🌐 Changing bindIp to 0.0.0.0..."
sudo sed -i 's/bindIp: 127.0.0.1/bindIp: 0.0.0.0/' /etc/mongod.conf

echo "🔁 Restarting MongoDB..."
sudo systemctl restart mongod

echo "🎉 MongoDB setup complete!"
echo "👉 Run 'mongosh' to enter MongoDB shell"

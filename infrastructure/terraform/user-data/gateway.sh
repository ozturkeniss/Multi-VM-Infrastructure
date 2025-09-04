#!/bin/bash

# Update system
apt-get update
apt-get upgrade -y

# Install Docker
apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

# Add ubuntu user to docker group
usermod -aG docker ubuntu

# Install Go
wget https://go.dev/dl/go1.24.6.linux-amd64.tar.gz
tar -C /usr/local -xzf go1.24.6.linux-amd64.tar.gz
echo 'export PATH=$PATH:/usr/local/go/bin' >> /home/ubuntu/.bashrc
echo 'export PATH=$PATH:/usr/local/go/bin' >> /etc/environment

# Install additional tools
apt-get install -y git htop curl wget unzip

# Create application directory
mkdir -p /opt/cluster-iac
chown ubuntu:ubuntu /opt/cluster-iac

# Create systemd service for the gateway
cat <<EOF > /etc/systemd/system/cluster-iac-gateway.service
[Unit]
Description=Cluster IAC API Gateway
After=network.target

[Service]
Type=simple
User=ubuntu
WorkingDirectory=/opt/cluster-iac
Environment=PRODUCT_SERVICE_URL=http://${api_services_private_ip}:8080
Environment=BASKET_SERVICE_URL=http://${api_services_private_ip}:8081
Environment=GATEWAY_PORT=8082
ExecStart=/opt/cluster-iac/gateway
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

# Enable the service (will start after deployment)
systemctl enable cluster-iac-gateway

# Install nginx for load balancing and SSL termination
apt-get install -y nginx

# Configure nginx
cat <<EOF > /etc/nginx/sites-available/cluster-iac
server {
    listen 80;
    server_name _;

    location / {
        proxy_pass http://localhost:8082;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    location /health {
        access_log off;
        proxy_pass http://localhost:8082/health;
    }
}
EOF

# Enable the site
ln -sf /etc/nginx/sites-available/cluster-iac /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default

# Start nginx
systemctl enable nginx
systemctl start nginx

# Create log directory
mkdir -p /var/log/cluster-iac
chown ubuntu:ubuntu /var/log/cluster-iac

echo "Gateway server setup completed" > /tmp/setup-complete

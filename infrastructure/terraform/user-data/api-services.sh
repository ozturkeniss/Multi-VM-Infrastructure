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
apt-get install -y git htop curl wget unzip postgresql-client redis-tools

# Create application directory
mkdir -p /opt/cluster-iac
chown ubuntu:ubuntu /opt/cluster-iac

# Create systemd service for product service
cat <<EOF > /etc/systemd/system/cluster-iac-product.service
[Unit]
Description=Cluster IAC Product Service
After=network.target

[Service]
Type=simple
User=ubuntu
WorkingDirectory=/opt/cluster-iac
Environment=DB_HOST=${storage_private_ip}
Environment=DB_PORT=5432
Environment=DB_USER=postgres
Environment=DB_PASSWORD=postgres
Environment=DB_NAME=cluster_iac
Environment=DB_SSLMODE=disable
Environment=SERVER_PORT=8080
ExecStart=/opt/cluster-iac/product
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

# Create systemd service for basket service
cat <<EOF > /etc/systemd/system/cluster-iac-basket.service
[Unit]
Description=Cluster IAC Basket Service
After=network.target

[Service]
Type=simple
User=ubuntu
WorkingDirectory=/opt/cluster-iac
Environment=REDIS_ADDR=${storage_private_ip}:6379
Environment=REDIS_PASSWORD=
Environment=REDIS_DB=0
Environment=BASKET_SERVER_PORT=8081
Environment=PRODUCT_GRPC_ADDR=localhost:50051
ExecStart=/opt/cluster-iac/basket
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

# Enable the services (will start after deployment)
systemctl enable cluster-iac-product
systemctl enable cluster-iac-basket

# Install monitoring tools
apt-get install -y prometheus-node-exporter

# Configure node exporter
systemctl enable prometheus-node-exporter
systemctl start prometheus-node-exporter

# Create log directory
mkdir -p /var/log/cluster-iac
chown ubuntu:ubuntu /var/log/cluster-iac

# Install health check script
cat <<EOF > /usr/local/bin/health-check.sh
#!/bin/bash

# Check product service
curl -f http://localhost:8080/health || exit 1

# Check basket service
curl -f http://localhost:8081/health || exit 1

echo "All services healthy"
EOF

chmod +x /usr/local/bin/health-check.sh

# Setup cron for health checks
echo "*/5 * * * * ubuntu /usr/local/bin/health-check.sh >> /var/log/cluster-iac/health-check.log 2>&1" >> /etc/crontab

echo "API Services server setup completed" > /tmp/setup-complete

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

# Install additional tools
apt-get install -y git htop curl wget unzip

# Format and mount additional EBS volume for database storage
mkfs.ext4 /dev/nvme1n1
mkdir -p /data
mount /dev/nvme1n1 /data
echo '/dev/nvme1n1 /data ext4 defaults,nofail 0 2' >> /etc/fstab

# Set permissions
chown ubuntu:ubuntu /data

# Create PostgreSQL data directory
mkdir -p /data/postgresql
chown 999:999 /data/postgresql

# Create Redis data directory
mkdir -p /data/redis
chown 999:999 /data/redis

# Create docker-compose file for storage services
cat <<EOF > /opt/docker-compose-storage.yml
version: '3.8'

services:
  postgres:
    image: postgres:16-alpine
    container_name: cluster_iac_postgres
    environment:
      POSTGRES_DB: cluster_iac
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: postgres
    ports:
      - "5432:5432"
    volumes:
      - /data/postgresql:/var/lib/postgresql/data
    networks:
      - storage_network
    restart: unless-stopped
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U postgres"]
      interval: 10s
      timeout: 5s
      retries: 5

  redis:
    image: redis:7-alpine
    container_name: cluster_iac_redis
    ports:
      - "6379:6379"
    volumes:
      - /data/redis:/data
    networks:
      - storage_network
    restart: unless-stopped
    command: redis-server --appendonly yes --maxmemory 512mb --maxmemory-policy allkeys-lru
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 10s
      timeout: 5s
      retries: 5

networks:
  storage_network:
    driver: bridge
EOF

# Create systemd service for storage services
cat <<EOF > /etc/systemd/system/cluster-iac-storage.service
[Unit]
Description=Cluster IAC Storage Services
Requires=docker.service
After=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=/opt
ExecStart=/usr/bin/docker compose -f docker-compose-storage.yml up -d
ExecStop=/usr/bin/docker compose -f docker-compose-storage.yml down
TimeoutStartSec=0

[Install]
WantedBy=multi-user.target
EOF

# Enable and start the storage services
systemctl enable cluster-iac-storage
systemctl start cluster-iac-storage

# Install monitoring tools
apt-get install -y prometheus-node-exporter

# Configure node exporter
systemctl enable prometheus-node-exporter
systemctl start prometheus-node-exporter

# Setup PostgreSQL backup script
cat <<EOF > /usr/local/bin/postgres-backup.sh
#!/bin/bash

BACKUP_DIR="/data/backups/postgresql"
mkdir -p \$BACKUP_DIR

# Create backup
docker exec cluster_iac_postgres pg_dump -U postgres cluster_iac > \$BACKUP_DIR/backup_\$(date +%Y%m%d_%H%M%S).sql

# Keep only last 7 days of backups
find \$BACKUP_DIR -name "backup_*.sql" -mtime +7 -delete

echo "PostgreSQL backup completed: \$(date)"
EOF

chmod +x /usr/local/bin/postgres-backup.sh

# Setup Redis backup script
cat <<EOF > /usr/local/bin/redis-backup.sh
#!/bin/bash

BACKUP_DIR="/data/backups/redis"
mkdir -p \$BACKUP_DIR

# Create backup
docker exec cluster_iac_redis redis-cli BGSAVE
sleep 5
docker cp cluster_iac_redis:/data/dump.rdb \$BACKUP_DIR/dump_\$(date +%Y%m%d_%H%M%S).rdb

# Keep only last 7 days of backups
find \$BACKUP_DIR -name "dump_*.rdb" -mtime +7 -delete

echo "Redis backup completed: \$(date)"
EOF

chmod +x /usr/local/bin/redis-backup.sh

# Setup cron for backups
echo "0 2 * * * root /usr/local/bin/postgres-backup.sh >> /var/log/postgres-backup.log 2>&1" >> /etc/crontab
echo "0 3 * * * root /usr/local/bin/redis-backup.sh >> /var/log/redis-backup.log 2>&1" >> /etc/crontab

# Create health check script
cat <<EOF > /usr/local/bin/storage-health-check.sh
#!/bin/bash

# Check PostgreSQL
docker exec cluster_iac_postgres pg_isready -U postgres || exit 1

# Check Redis
docker exec cluster_iac_redis redis-cli ping || exit 1

echo "All storage services healthy"
EOF

chmod +x /usr/local/bin/storage-health-check.sh

# Setup cron for health checks
echo "*/5 * * * * ubuntu /usr/local/bin/storage-health-check.sh >> /var/log/storage-health.log 2>&1" >> /etc/crontab

echo "Storage server setup completed" > /tmp/setup-complete

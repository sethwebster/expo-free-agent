# Example 5: Deploy Controller to VPS

Production deployment guide for running the controller on a remote server.

## Prerequisites

- VPS with Ubuntu 22.04 LTS (or similar)
- Root or sudo access
- Domain name (optional but recommended)
- 2+ GB RAM, 20+ GB disk

## Recommended VPS Providers

- **DigitalOcean** - $12/month (2 GB RAM, 50 GB SSD)
- **Linode** - $12/month (2 GB RAM, 50 GB SSD)
- **Hetzner** - €4.51/month (2 GB RAM, 40 GB SSD)
- **Vultr** - $12/month (2 GB RAM, 55 GB SSD)

## Step 1: Provision VPS

### Create Droplet/Instance

```bash
# Example: DigitalOcean CLI
doctl compute droplet create expo-controller \
  --image ubuntu-22-04-x64 \
  --size s-2vcpu-2gb \
  --region nyc1 \
  --ssh-keys YOUR_SSH_KEY_ID

# Get IP address
doctl compute droplet list
```

### Configure DNS (Optional)

```bash
# Point domain to VPS IP
# Add A record:
builds.example.com → 165.232.123.45
```

## Step 2: Initial Server Setup

SSH into server:

```bash
ssh root@165.232.123.45
```

### Update System

```bash
apt update && apt upgrade -y
```

### Create User

```bash
# Create non-root user
adduser expo
usermod -aG sudo expo

# Setup SSH key
mkdir -p /home/expo/.ssh
cp /root/.ssh/authorized_keys /home/expo/.ssh/
chown -R expo:expo /home/expo/.ssh
chmod 700 /home/expo/.ssh
chmod 600 /home/expo/.ssh/authorized_keys

# Switch to new user
su - expo
```

### Configure Firewall

```bash
# Install UFW
sudo apt install -y ufw

# Allow SSH
sudo ufw allow OpenSSH

# Allow HTTP/HTTPS
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp

# Enable firewall
sudo ufw enable

# Verify
sudo ufw status
```

## Step 3: Install Dependencies

### Install Bun

```bash
curl -fsSL https://bun.sh/install | bash

# Add to PATH
echo 'export PATH="$HOME/.bun/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc

# Verify
bun --version
```

### Install Git

```bash
sudo apt install -y git
```

### Install Build Tools

```bash
sudo apt install -y build-essential
```

## Step 4: Clone and Setup Repository

```bash
# Clone repository
cd ~
git clone https://github.com/expo/expo-free-agent.git
cd expo-free-agent

# Install dependencies
bun install

# Build if needed
bun run build
```

## Step 5: Configure Environment

### Create .env File

```bash
cat > .env <<EOF
# Server configuration
PORT=3000
NODE_ENV=production

# API authentication
CONTROLLER_API_KEY=$(openssl rand -base64 32)

# Storage paths
DATA_DIR=/home/expo/expo-free-agent/data
STORAGE_DIR=/home/expo/expo-free-agent/storage

# Logging
LOG_LEVEL=info
LOG_FILE=/home/expo/expo-free-agent/logs/controller.log

# Optional: Database
# DATABASE_URL=file:/home/expo/expo-free-agent/data/controller.db
EOF

# Secure .env
chmod 600 .env
```

### Create Directories

```bash
mkdir -p data storage logs
chmod 700 data storage logs
```

## Step 6: Setup Systemd Service

Create service file:

```bash
sudo nano /etc/systemd/system/expo-controller.service
```

Add content:

```ini
[Unit]
Description=Expo Free Agent Controller
After=network.target

[Service]
Type=simple
User=expo
WorkingDirectory=/home/expo/expo-free-agent
Environment=NODE_ENV=production
EnvironmentFile=/home/expo/expo-free-agent/.env
ExecStart=/home/expo/.bun/bin/bun run packages/controller/src/index.ts
Restart=always
RestartSec=10
StandardOutput=append:/home/expo/expo-free-agent/logs/controller.log
StandardError=append:/home/expo/expo-free-agent/logs/error.log

# Security
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/home/expo/expo-free-agent/data /home/expo/expo-free-agent/storage /home/expo/expo-free-agent/logs

[Install]
WantedBy=multi-user.target
```

### Enable and Start Service

```bash
# Reload systemd
sudo systemctl daemon-reload

# Enable service
sudo systemctl enable expo-controller

# Start service
sudo systemctl start expo-controller

# Check status
sudo systemctl status expo-controller

# View logs
sudo journalctl -u expo-controller -f
```

## Step 7: Setup Reverse Proxy (Nginx)

### Install Nginx

```bash
sudo apt install -y nginx
```

### Configure Nginx

```bash
sudo nano /etc/nginx/sites-available/expo-controller
```

Add configuration:

```nginx
server {
    listen 80;
    server_name builds.example.com;

    # Redirect to HTTPS
    return 301 https://$server_name$request_uri;
}

server {
    listen 443 ssl http2;
    server_name builds.example.com;

    # SSL certificates (will be configured by Certbot)
    ssl_certificate /etc/letsencrypt/live/builds.example.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/builds.example.com/privkey.pem;

    # SSL configuration
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers on;

    # Logging
    access_log /var/log/nginx/expo-controller-access.log;
    error_log /var/log/nginx/expo-controller-error.log;

    # Proxy settings
    client_max_body_size 500M;  # Allow large uploads

    location / {
        proxy_pass http://localhost:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_cache_bypass $http_upgrade;

        # Timeouts for large uploads
        proxy_connect_timeout 600;
        proxy_send_timeout 600;
        proxy_read_timeout 600;
        send_timeout 600;
    }
}
```

### Enable Site

```bash
sudo ln -s /etc/nginx/sites-available/expo-controller /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl reload nginx
```

## Step 8: Setup SSL with Let's Encrypt

```bash
# Install Certbot
sudo apt install -y certbot python3-certbot-nginx

# Obtain certificate
sudo certbot --nginx -d builds.example.com

# Test auto-renewal
sudo certbot renew --dry-run
```

## Step 9: Configure Backups

### Database Backup Script

```bash
cat > ~/backup-controller.sh <<'EOF'
#!/bin/bash
BACKUP_DIR="/home/expo/backups"
DATE=$(date +%Y%m%d_%H%M%S)

mkdir -p $BACKUP_DIR

# Backup database
cp /home/expo/expo-free-agent/data/controller.db \
   $BACKUP_DIR/controller-$DATE.db

# Backup storage (optional, can be large)
# tar -czf $BACKUP_DIR/storage-$DATE.tar.gz \
#    /home/expo/expo-free-agent/storage

# Keep only last 7 days
find $BACKUP_DIR -name "controller-*.db" -mtime +7 -delete

echo "Backup completed: $DATE"
EOF

chmod +x ~/backup-controller.sh
```

### Schedule Backups

```bash
# Add to crontab
crontab -e

# Add line (daily at 2 AM):
0 2 * * * /home/expo/backup-controller.sh
```

## Step 10: Monitoring Setup

### Install Monitoring Tools

```bash
# Install htop for resource monitoring
sudo apt install -y htop

# Install node exporter for Prometheus (optional)
wget https://github.com/prometheus/node_exporter/releases/download/v1.7.0/node_exporter-1.7.0.linux-amd64.tar.gz
tar -xzf node_exporter-*.tar.gz
sudo mv node_exporter-*/node_exporter /usr/local/bin/
rm -rf node_exporter-*
```

### Create Health Check Script

```bash
cat > ~/health-check.sh <<'EOF'
#!/bin/bash
CONTROLLER_URL="https://builds.example.com"

# Check HTTP status
STATUS=$(curl -s -o /dev/null -w "%{http_code}" $CONTROLLER_URL/health)

if [ "$STATUS" != "200" ]; then
    echo "Controller unhealthy! Status: $STATUS"
    # Send alert (configure email or Slack webhook)
    curl -X POST https://your-slack-webhook-url \
        -H 'Content-Type: application/json' \
        -d '{"text":"⚠️ Expo Controller is down!"}'
fi
EOF

chmod +x ~/health-check.sh

# Run every 5 minutes
crontab -e
# Add: */5 * * * * /home/expo/health-check.sh
```

## Step 11: Security Hardening

### Disable Root Login

```bash
sudo nano /etc/ssh/sshd_config

# Change:
PermitRootLogin no
PasswordAuthentication no

# Restart SSH
sudo systemctl restart sshd
```

### Install Fail2Ban

```bash
sudo apt install -y fail2ban

# Configure
sudo cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.local
sudo systemctl enable fail2ban
sudo systemctl start fail2ban
```

### Setup Log Rotation

```bash
sudo nano /etc/logrotate.d/expo-controller
```

Add:

```
/home/expo/expo-free-agent/logs/*.log {
    daily
    rotate 14
    compress
    delaycompress
    notifempty
    create 0640 expo expo
    sharedscripts
    postrotate
        systemctl reload expo-controller
    endscript
}
```

## Step 12: Test Deployment

### From Local Machine

```bash
# Set controller URL
export EXPO_CONTROLLER_URL="https://builds.example.com"
export EXPO_CONTROLLER_API_KEY="your-api-key"

# Test health endpoint
curl https://builds.example.com/health

# Submit test build
cd ~/test-app
expo-build submit --platform ios
```

### Monitor Logs

```bash
# On VPS
sudo journalctl -u expo-controller -f

# Nginx access log
sudo tail -f /var/log/nginx/expo-controller-access.log
```

## Maintenance

### Update Controller

```bash
cd ~/expo-free-agent
git pull
bun install
sudo systemctl restart expo-controller
```

### Check Disk Space

```bash
# View usage
df -h

# Clean old builds (if needed)
find ~/expo-free-agent/storage -type f -mtime +30 -delete
```

### View Statistics

```bash
# Controller stats
curl https://builds.example.com/health | jq

# System stats
htop
```

## Troubleshooting

### Service Won't Start

```bash
# Check logs
sudo journalctl -u expo-controller -n 50

# Check configuration
systemctl show expo-controller

# Test manually
cd ~/expo-free-agent
bun run packages/controller/src/index.ts
```

### High Memory Usage

```bash
# Check process
ps aux | grep bun

# Restart service
sudo systemctl restart expo-controller

# Consider upgrading VPS if consistently high
```

### SSL Certificate Issues

```bash
# Renew manually
sudo certbot renew

# Check expiry
sudo certbot certificates
```

## Cost Analysis

**Monthly costs:**
- VPS: $12/month
- Domain: $1/month (annual)
- SSL: Free (Let's Encrypt)
- **Total: ~$13/month**

**vs Cloud Build Service:**
- Typical: $50-100/month for 500-1000 builds
- **Savings: $37-87/month**

## Next Steps

- **Add Workers:** Connect worker Macs to this controller
- **Setup Monitoring:** Grafana + Prometheus
- **Configure CI/CD:** GitHub Actions → This controller
- **Scale:** Add load balancer for multiple controllers

## Resources

- [DigitalOcean Deployment](https://docs.digitalocean.com/products/droplets/)
- [Nginx Best Practices](https://www.nginx.com/blog/nginx-best-practices/)
- [Systemd Service](https://www.freedesktop.org/software/systemd/man/systemd.service.html)

---

**Time to complete:** ~2 hours
**Skill level:** Advanced (server administration)
**Ongoing maintenance:** ~30 minutes/month

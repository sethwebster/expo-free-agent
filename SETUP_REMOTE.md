# Remote Hosting Guide - Expo Free Agent Controller

Complete guide for deploying the Expo Free Agent Controller to a remote server for production use.

## Architecture Overview

**Production Setup:**
```
┌─────────────────┐         ┌──────────────────────┐
│   CLI Client    │────────▶│  Remote Controller   │
│   (Developer)   │         │   (VPS/Cloud)        │
└─────────────────┘         └──────────────────────┘
                                      ▲
                                      │
                            ┌─────────┴─────────┐
                            │                   │
                      ┌─────┴──────┐     ┌─────┴──────┐
                      │  Worker 1  │     │  Worker 2  │
                      │   (macOS)  │     │   (macOS)  │
                      └────────────┘     └────────────┘
```

**Controller:** Hosted on cloud server (DigitalOcean, AWS, etc.)
**Workers:** Local macOS machines polling the remote controller
**CLI:** Developers submit builds from anywhere

## Prerequisites

### Remote Server Requirements

- **OS:** Ubuntu 20.04+ or Debian 11+
- **RAM:** 2GB minimum, 4GB recommended
- **Storage:** 50GB+ (for build artifacts)
- **Network:** Public IP address, ports 80/443 open
- **Domain:** Optional but recommended (e.g., `builds.yourcompany.com`)

### Local Requirements

- **SSH access** to remote server
- **Domain DNS** configured (if using custom domain)
- **SSL certificate** (Let's Encrypt recommended)

## Option 1: DigitalOcean Droplet

### Step 1: Create Droplet

1. Go to [DigitalOcean](https://www.digitalocean.com)
2. Create Droplet:
   - **Image:** Ubuntu 22.04 LTS
   - **Plan:** Basic - $12/month (2GB RAM, 50GB SSD)
   - **Region:** Choose closest to workers
   - **Authentication:** SSH key
3. Note the IP address

### Step 2: Configure DNS (Optional)

Point your domain to the droplet:

```
A Record:  builds.yourcompany.com → <droplet-ip>
```

Wait for DNS propagation (5-60 minutes).

### Step 3: SSH to Server

```bash
ssh root@<droplet-ip>
# or
ssh root@builds.yourcompany.com
```

## Option 2: AWS EC2

### Step 1: Launch Instance

1. Go to AWS EC2 Console
2. Launch Instance:
   - **AMI:** Ubuntu Server 22.04 LTS
   - **Instance Type:** t3.small (2 vCPU, 2GB RAM)
   - **Storage:** 50GB gp3
   - **Security Group:** Allow ports 22, 80, 443
3. Download key pair
4. Note public IP

### Step 2: SSH to Instance

```bash
chmod 400 your-key.pem
ssh -i your-key.pem ubuntu@<instance-ip>
```

## Server Setup (All Providers)

### Step 1: Install Dependencies

```bash
# Update system
sudo apt update && sudo apt upgrade -y

# Install Node.js and Bun
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt install -y nodejs

curl -fsSL https://bun.sh/install | bash
source ~/.bashrc

# Install git
sudo apt install -y git

# Install nginx (reverse proxy)
sudo apt install -y nginx

# Install certbot (SSL)
sudo apt install -y certbot python3-certbot-nginx
```

### Step 2: Create Application User

```bash
# Create dedicated user
sudo useradd -m -s /bin/bash expo-controller
sudo su - expo-controller
```

### Step 3: Clone Repository

```bash
git clone <repository-url> expo-free-agent
cd expo-free-agent
```

### Step 4: Install Application Dependencies

```bash
# Install controller dependencies
cd packages/controller
bun install
cd ../..
```

### Step 5: Configure Application

```bash
# Generate secure API key
export API_KEY=$(openssl rand -hex 32)
echo "Generated API Key: $API_KEY"
# SAVE THIS KEY - you'll need it for workers and CLI

# Create environment file
cat > packages/controller/.env << EOF
CONTROLLER_API_KEY=$API_KEY
PORT=3000
NODE_ENV=production
EOF

# Create data directories
mkdir -p packages/controller/data
mkdir -p packages/controller/storage

# Set permissions
chmod 700 packages/controller/data
chmod 700 packages/controller/storage
```

### Step 6: Test Controller

```bash
cd packages/controller
bun run start
```

**Expected output:**
```
🚀 Expo Free Agent Controller
📍 Server:   http://localhost:3000
```

Press **Ctrl+C** to stop. If successful, proceed to systemd setup.

## Production Deployment

### Step 1: Create Systemd Service

Exit to root user:
```bash
exit  # Back to root/ubuntu user
```

Create service file:
```bash
sudo nano /etc/systemd/system/expo-controller.service
```

Paste configuration:
```ini
[Unit]
Description=Expo Free Agent Controller
After=network.target

[Service]
Type=simple
User=expo-controller
WorkingDirectory=/home/expo-controller/expo-free-agent/packages/controller
Environment="CONTROLLER_API_KEY=<your-api-key>"
Environment="PORT=3000"
Environment="NODE_ENV=production"
ExecStart=/home/expo-controller/.bun/bin/bun run start
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
```

**Replace `<your-api-key>`** with your generated API key.

Save and exit (**Ctrl+X**, **Y**, **Enter**).

### Step 2: Start Service

```bash
# Reload systemd
sudo systemctl daemon-reload

# Enable service (start on boot)
sudo systemctl enable expo-controller

# Start service
sudo systemctl start expo-controller

# Check status
sudo systemctl status expo-controller
```

**Expected output:**
```
● expo-controller.service - Expo Free Agent Controller
   Active: active (running)
```

View logs:
```bash
sudo journalctl -u expo-controller -f
```

## Configure Nginx Reverse Proxy

### Step 1: Create Nginx Config

```bash
sudo nano /etc/nginx/sites-available/expo-controller
```

**Without SSL (initial setup):**
```nginx
server {
    listen 80;
    server_name builds.yourcompany.com;  # or use IP address

    client_max_body_size 500M;  # Allow large build uploads

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
        proxy_read_timeout 300s;
        proxy_connect_timeout 300s;
        proxy_send_timeout 300s;
    }
}
```

### Step 2: Enable Site

```bash
# Enable site
sudo ln -s /etc/nginx/sites-available/expo-controller /etc/nginx/sites-enabled/

# Remove default site
sudo rm /etc/nginx/sites-enabled/default

# Test configuration
sudo nginx -t

# Restart nginx
sudo systemctl restart nginx
```

### Step 3: Configure Firewall

```bash
# Allow HTTP, HTTPS, SSH
sudo ufw allow 22/tcp
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp

# Enable firewall
sudo ufw --force enable

# Check status
sudo ufw status
```

### Step 4: Test HTTP Access

From your local machine:
```bash
curl http://builds.yourcompany.com/api/builds/active \
  -H "X-API-Key: <your-api-key>"
```

**Expected:** `{"builds":[]}`

## SSL Setup (HTTPS)

### Step 1: Obtain Certificate

```bash
sudo certbot --nginx -d builds.yourcompany.com
```

Follow prompts:
- Enter email
- Agree to terms
- Choose: Redirect HTTP to HTTPS

### Step 2: Verify SSL

Certbot automatically updates nginx config. Verify:
```bash
sudo nginx -t
sudo systemctl reload nginx
```

Test HTTPS:
```bash
curl https://builds.yourcompany.com/api/builds/active \
  -H "X-API-Key: <your-api-key>"
```

### Step 3: Auto-Renewal

Certbot auto-renews. Test renewal:
```bash
sudo certbot renew --dry-run
```

## Configure Workers (Remote)

On each macOS worker machine:

### Step 1: Install Worker GUI

```bash
cd expo-free-agent/free-agent
swift build
.build/debug/FreeAgent
```

### Step 2: Configure Worker Settings

1. Click menu bar icon
2. Click **"Settings..."**
3. Set configuration:
   - **Controller URL:** `https://builds.yourcompany.com`
   - **API Key:** `<your-api-key>`
   - **Worker Name:** `MacBook-Office-1`
   - **Auto-start:** ✓
4. Click **Save**

### Step 3: Verify Registration

Check controller logs:
```bash
sudo journalctl -u expo-controller -f
```

Should see:
```
[timestamp] POST /api/workers/register
Worker registered: <worker-id>
```

## Configure CLI (Remote)

On developer machines:

```bash
cd expo-free-agent/cli

# Configure controller URL
bun run dev config set controller-url https://builds.yourcompany.com

# Set API key
export EXPO_CONTROLLER_API_KEY="<your-api-key>"

# Or save to config
bun run dev config set api-key <your-api-key>

# Test connection
bun run dev list
```

## Production Checklist

- [ ] Controller running as systemd service
- [ ] Service auto-starts on boot
- [ ] Nginx reverse proxy configured
- [ ] SSL certificate installed and auto-renewing
- [ ] Firewall configured (ports 80, 443, 22 only)
- [ ] Workers connected and registered
- [ ] CLI configured to use remote URL
- [ ] Test build submission succeeds
- [ ] Build artifacts stored correctly
- [ ] Logs accessible via journalctl

## Monitoring

### Check Controller Status

```bash
sudo systemctl status expo-controller
```

### View Live Logs

```bash
sudo journalctl -u expo-controller -f
```

### View Error Logs Only

```bash
sudo journalctl -u expo-controller -p err -f
```

### Check Disk Usage

```bash
# Check storage directory size
du -sh /home/expo-controller/expo-free-agent/packages/controller/storage

# Check available space
df -h
```

### Check Active Builds

```bash
curl https://builds.yourcompany.com/api/builds/active \
  -H "X-API-Key: <your-api-key>"
```

## Maintenance

### Update Application

```bash
# Switch to app user
sudo su - expo-controller

# Pull latest code
cd expo-free-agent
git pull

# Update dependencies
cd packages/controller
bun install

# Exit to root
exit

# Restart service
sudo systemctl restart expo-controller
```

### Backup Database

```bash
# Create backup script
sudo nano /home/expo-controller/backup.sh
```

```bash
#!/bin/bash
DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="/home/expo-controller/backups"
DB_PATH="/home/expo-controller/expo-free-agent/packages/controller/data/controller.db"

mkdir -p $BACKUP_DIR
cp $DB_PATH $BACKUP_DIR/controller_$DATE.db

# Keep only last 7 days
find $BACKUP_DIR -name "controller_*.db" -mtime +7 -delete
```

Make executable and add to cron:
```bash
sudo chmod +x /home/expo-controller/backup.sh
sudo crontab -e -u expo-controller
```

Add line:
```
0 2 * * * /home/expo-controller/backup.sh
```

### Clean Old Build Artifacts

```bash
# Find builds older than 30 days
find /home/expo-controller/expo-free-agent/packages/controller/storage \
  -type f -mtime +30

# Delete after verification
find /home/expo-controller/expo-free-agent/packages/controller/storage \
  -type f -mtime +30 -delete
```

## Scaling

### Add More Workers

Repeat worker setup on additional macOS machines. Each worker:
- Connects to same controller URL
- Uses same API key
- Gets unique worker ID
- Polls independently

### Increase Storage

If running out of disk space:

**DigitalOcean:**
1. Create Volume
2. Attach to Droplet
3. Mount at `/mnt/builds`
4. Update storage path in `.env`:
   ```bash
   STORAGE_PATH=/mnt/builds
   ```
5. Restart service

**AWS:**
1. Create EBS Volume
2. Attach to instance
3. Format and mount
4. Update storage path

### Load Balancing (Advanced)

For multiple controllers:
1. Set up multiple controller instances
2. Configure shared database (PostgreSQL)
3. Use shared storage (S3, NFS)
4. Add load balancer (nginx, HAProxy)

## Troubleshooting

### Controller won't start

```bash
# Check service status
sudo systemctl status expo-controller

# View logs
sudo journalctl -u expo-controller -n 50

# Common issues:
# 1. Port already in use
sudo lsof -i:3000

# 2. Permission issues
sudo chown -R expo-controller:expo-controller /home/expo-controller/expo-free-agent
```

### Workers can't connect

**Check firewall:**
```bash
sudo ufw status
```

**Check nginx:**
```bash
sudo nginx -t
sudo systemctl status nginx
```

**Test from worker:**
```bash
curl -v https://builds.yourcompany.com/api/builds/active \
  -H "X-API-Key: <your-api-key>"
```

### SSL certificate issues

```bash
# Renew manually
sudo certbot renew

# Check expiry
sudo certbot certificates

# Restart nginx
sudo systemctl restart nginx
```

### Out of disk space

```bash
# Check space
df -h

# Find large files
du -sh /home/expo-controller/expo-free-agent/packages/controller/storage/*

# Clean old builds
# (Use maintenance script above)
```

## Security Best Practices

### API Key Security

- **Never commit** API key to git
- **Rotate keys** quarterly
- **Use environment variables** only
- **Different keys** for dev/prod

### Network Security

- **Restrict SSH:** Only from known IPs
  ```bash
  sudo ufw allow from <your-ip> to any port 22
  ```
- **Enable fail2ban:**
  ```bash
  sudo apt install fail2ban
  sudo systemctl enable fail2ban
  ```

### Application Security

- **Rate limiting** (add to nginx):
  ```nginx
  limit_req_zone $binary_remote_addr zone=api:10m rate=10r/s;
  limit_req zone=api burst=20;
  ```
- **File size limits** (already in nginx config)
- **Regular updates:**
  ```bash
  sudo apt update && sudo apt upgrade -y
  ```

## Cost Estimates

### DigitalOcean
- **Droplet:** $12/month (2GB RAM, 50GB SSD)
- **Volume:** $10/month (100GB extra storage)
- **Total:** ~$22/month

### AWS EC2
- **t3.small:** ~$15/month (2 vCPU, 2GB RAM)
- **EBS:** ~$5/month (50GB gp3)
- **Total:** ~$20/month

### Domain + SSL
- **Domain:** $10-15/year
- **SSL:** Free (Let's Encrypt)

## Next Steps

- Set up monitoring (Prometheus, Grafana)
- Configure automated backups
- Set up log aggregation
- Add build notifications (Slack, Discord)
- Implement build queue priority
- Add worker health checks

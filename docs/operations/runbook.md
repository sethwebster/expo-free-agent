# Operations Runbook

Day-to-day operational procedures for Expo Free Agent in production.

## Daily Operations

### Morning Health Check (5 minutes)

```bash
# 1. Check controller status
curl https://builds.example.com/health | jq

# Expected:
# {
#   "status": "healthy",
#   "activeWorkers": 4,
#   "queueDepth": 0
# }

# 2. Check worker status
# Visit: https://builds.example.com
# Verify all workers show "online"

# 3. Review failed builds (if any)
curl -H "Authorization: Bearer $API_KEY" \
  "https://builds.example.com/api/builds?status=failed&since=$(date -u -d '24 hours ago' +%Y-%m-%dT%H:%M:%SZ)" \
  | jq '.total'

# 4. Check disk space
ssh user@builds.example.com "df -h"

# Should have >20GB free
```

### Monitor Build Queue

```bash
# Check queue depth
curl https://builds.example.com/health | jq '.stats.queueDepth'

# Alert if >10 builds pending for >15 minutes
```

### Review Logs

```bash
# Controller logs
ssh user@builds.example.com "sudo journalctl -u expo-controller --since '1 hour ago' | grep ERROR"

# Look for patterns:
# - Authentication failures
# - Database errors
# - Worker disconnections
```

---

## Weekly Maintenance

### Database Optimization (Sundays, 2 AM)

```bash
# SSH to controller
ssh user@builds.example.com

# Backup database
cp ~/expo-free-agent/data/controller.db \
   ~/backups/controller-$(date +%Y%m%d).db

# Optimize
sqlite3 ~/expo-free-agent/data/controller.db << EOF
VACUUM;
REINDEX;
ANALYZE;
.quit
EOF

# Verify integrity
sqlite3 ~/expo-free-agent/data/controller.db "PRAGMA integrity_check;"

# Expected: "ok"
```

### Clean Old Builds

```bash
# Remove builds older than 90 days
ssh user@builds.example.com
cd ~/expo-free-agent
find storage/builds -type d -mtime +90 -exec rm -rf {} +

# Or use built-in cleanup (future feature):
# curl -X POST -H "Authorization: Bearer $API_KEY" \
#   https://builds.example.com/api/admin/cleanup
```

### Review Metrics

```bash
# Build success rate (last 7 days)
curl -H "Authorization: Bearer $API_KEY" \
  "https://builds.example.com/api/stats/summary?days=7" | jq

# Expected: >95% success rate

# Average build time
# Should be <15 minutes for iOS, <10 minutes for Android
```

---

## Monthly Tasks

### Update Dependencies

```bash
# SSH to controller
ssh user@builds.example.com
cd ~/expo-free-agent

# Pull latest
git pull

# Update packages
bun update

# Run tests
bun test

# Restart controller
sudo systemctl restart expo-controller

# Verify
curl https://builds.example.com/health
```

### Certificate Renewal

```bash
# Let's Encrypt auto-renews, but verify:
ssh user@builds.example.com
sudo certbot certificates

# Should show: "Certificate will not expire soon"

# Test renewal
sudo certbot renew --dry-run
```

### Worker Health Check

For each worker Mac:

```bash
# Check uptime
uptime

# Check disk space
df -h

# Check memory
vm_stat | grep "Pages free" | awk '{print $3}' | sed 's/\.//' | awk '{print $1 * 4096 / 1024 / 1024 " MB free"}'

# Update macOS (if needed)
# System Settings → General → Software Update

# Update Xcode (if needed)
# App Store → Updates

# Restart worker app
# Menu bar → Quit → Reopen
```

---

## Emergency Procedures

### Controller Down

**Symptoms:**
- Health endpoint not responding
- Builds failing with connection errors

**Steps:**

```bash
# 1. Check if service is running
ssh user@builds.example.com
sudo systemctl status expo-controller

# 2. If stopped, start it
sudo systemctl start expo-controller

# 3. Check logs for errors
sudo journalctl -u expo-controller -n 100

# 4. Common fixes:

# Database locked:
pkill -f controller
rm data/controller.db-shm data/controller.db-wal
sudo systemctl start expo-controller

# Port in use:
kill $(lsof -t -i:3000)
sudo systemctl start expo-controller

# Out of disk space:
df -h
find storage/builds -mtime +30 -exec rm -rf {} +
sudo systemctl start expo-controller

# 5. Verify recovery
curl https://builds.example.com/health
```

### Worker Offline

**Symptoms:**
- Worker shows "offline" in dashboard
- Builds pending, not being assigned

**Steps:**

```bash
# 1. Check worker Mac
# Physical access or VNC required

# 2. Check worker app is running
ps aux | grep FreeAgent

# 3. If not running, start it
open /Applications/FreeAgent.app

# 4. Check logs
# Menu bar → View Logs

# 5. Reconnect if needed
# Menu bar → Connect

# 6. If still failing:
# - Restart Mac
# - Reinstall worker app
# - Check network connectivity
```

### Database Corruption

**Symptoms:**
```
SQLITE_CORRUPT: database disk image is malformed
```

**Steps:**

```bash
# 1. Stop controller
sudo systemctl stop expo-controller

# 2. Backup corrupted database
cp data/controller.db data/controller.db.corrupted

# 3. Try to repair
sqlite3 data/controller.db << EOF
.clone data/controller-repaired.db
.quit
EOF

# 4. If repair works:
mv data/controller.db data/controller.db.backup
mv data/controller-repaired.db data/controller.db

# 5. If repair fails, restore from backup:
cp ~/backups/controller-latest.db data/controller.db

# 6. Start controller
sudo systemctl start expo-controller

# 7. Verify
curl https://builds.example.com/health
```

### Disk Full

**Symptoms:**
```
Error: ENOSPC: no space left on device
```

**Steps:**

```bash
# 1. Check disk usage
df -h

# 2. Find large directories
du -sh ~/expo-free-agent/* | sort -h

# 3. Clean old builds
cd ~/expo-free-agent
find storage/builds -mtime +7 -exec rm -rf {} +

# 4. Clean logs
sudo journalctl --vacuum-time=7d

# 5. Restart controller
sudo systemctl restart expo-controller
```

### Memory Exhaustion

**Symptoms:**
- Controller becomes unresponsive
- Workers report timeout errors
- High swap usage

**Steps:**

```bash
# 1. Check memory
free -h

# 2. Identify memory hog
ps aux --sort=-%mem | head

# 3. Restart controller
sudo systemctl restart expo-controller

# 4. If recurring, upgrade VPS
# 2 GB → 4 GB RAM recommended
```

---

## Maintenance Windows

### Scheduled Maintenance

**When:** 1st Sunday of month, 2-4 AM UTC

**Tasks:**
1. Notify users 72 hours in advance
2. Disable new build submissions
3. Wait for running builds to complete
4. Update controller and workers
5. Run database optimization
6. Test end-to-end build
7. Re-enable build submissions

**Notification:**

```bash
# Set maintenance mode
curl -X POST -H "Authorization: Bearer $API_KEY" \
  https://builds.example.com/api/admin/maintenance \
  -d '{"enabled": true, "message": "Scheduled maintenance"}'

# Users see:
# "503 Service Unavailable - Scheduled maintenance (back at 4 AM UTC)"
```

---

## Monitoring & Alerts

### Key Metrics to Monitor

| Metric | Warning | Critical | Action |
|--------|---------|----------|--------|
| Queue depth | >10 | >20 | Add workers |
| Build failure rate | >10% | >25% | Investigate |
| Disk space | <20GB | <5GB | Clean builds |
| Controller CPU | >70% | >90% | Upgrade VPS |
| Controller Memory | >80% | >95% | Restart or upgrade |
| Worker offline | Any | >50% | Investigate network |

### Alert Destinations

```bash
# Slack webhook (recommended)
curl -X POST https://hooks.slack.com/services/YOUR/WEBHOOK \
  -H 'Content-Type: application/json' \
  -d '{"text": "⚠️ Alert: Queue depth is 15"}'

# Email (via sendmail or SMTP)
echo "Queue depth is 15" | mail -s "Alert" ops@example.com

# PagerDuty (for critical alerts)
curl -X POST https://events.pagerduty.com/v2/enqueue \
  -H 'Content-Type: application/json' \
  -d '{
    "routing_key": "YOUR_KEY",
    "event_action": "trigger",
    "payload": {
      "summary": "Controller down",
      "severity": "critical",
      "source": "builds.example.com"
    }
  }'
```

---

## Backup & Recovery

### Backup Schedule

- **Database:** Daily, 2 AM UTC (automated)
- **Configuration:** On change (manual)
- **Storage:** Weekly (optional, can be large)

### Automated Backup

Already configured if you followed [Example 5](../../examples/05-deploy-controller-vps/).

Verify cron:

```bash
crontab -l | grep backup
# Expected: 0 2 * * * /home/expo/backup-controller.sh
```

### Manual Backup

```bash
# Backup everything
tar -czf expo-backup-$(date +%Y%m%d).tar.gz \
  ~/expo-free-agent/data \
  ~/expo-free-agent/.env \
  ~/expo-free-agent/storage  # Optional, large

# Upload to S3 (if configured)
aws s3 cp expo-backup-*.tar.gz s3://your-bucket/backups/
```

### Disaster Recovery

**Scenario:** Complete server failure

**Recovery steps:**

```bash
# 1. Provision new VPS (same specs)

# 2. Install dependencies
# Follow: examples/05-deploy-controller-vps/README.md

# 3. Restore latest backup
scp local-machine:~/backups/controller-latest.db \
  user@new-server:~/expo-free-agent/data/controller.db

# 4. Restore .env
scp local-machine:~/backups/.env \
  user@new-server:~/expo-free-agent/.env

# 5. Start controller
sudo systemctl start expo-controller

# 6. Update DNS
# Point builds.example.com to new IP

# 7. Reconnect workers
# Workers will auto-reconnect when DNS updates

# 8. Verify
curl https://builds.example.com/health
```

**RTO (Recovery Time Objective):** 30 minutes
**RPO (Recovery Point Objective):** 24 hours (daily backups)

---

## Performance Tuning

### Optimize Database

```bash
# Add indices for common queries
sqlite3 data/controller.db << EOF
CREATE INDEX IF NOT EXISTS idx_builds_status ON builds(status);
CREATE INDEX IF NOT EXISTS idx_builds_created_at ON builds(created_at);
CREATE INDEX IF NOT EXISTS idx_jobs_status ON jobs(status);
.quit
EOF
```

### Optimize Storage

```bash
# Use SSD storage for better I/O
# Separate storage and database on different volumes
# Mount storage with noatime for less I/O
echo "/dev/sdb /home/expo/expo-free-agent/storage ext4 defaults,noatime 0 2" >> /etc/fstab
```

### Scale Workers

```bash
# Benchmark: 1 worker can handle ~50 builds/day
# Add workers as needed:

# Target: 200 builds/day
# Workers needed: 4

# Target: 1000 builds/day
# Workers needed: 20
```

---

## Troubleshooting Quick Reference

| Issue | Command | Fix |
|-------|---------|-----|
| Controller won't start | `sudo systemctl status expo-controller` | Check logs, fix error |
| Database locked | `pkill -f controller` | Kill processes, restart |
| Disk full | `df -h` | Clean old builds |
| Worker offline | Check Mac | Restart worker app |
| High queue depth | `curl .../health` | Add workers |
| Build timeout | Check worker logs | Increase timeout or optimize |

---

## Contacts

**On-Call Rotation:**
- Week 1: Alice (alice@example.com)
- Week 2: Bob (bob@example.com)
- Week 3: Carol (carol@example.com)

**Escalation:**
- L1: On-call engineer
- L2: Tech lead
- L3: Infrastructure team

**Vendor Support:**
- VPS: support@digitalocean.com
- DNS: support@cloudflare.com

---

**Last Updated:** 2026-01-28
**Review:** Monthly
**Owner:** DevOps Team

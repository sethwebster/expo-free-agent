# Deployment Guide

Production deployment, environment configuration, monitoring, and operational procedures for Elixir controller.

---

## Prerequisites

### System Requirements

**Production Server**:
- OS: Ubuntu 22.04 LTS or similar
- CPU: 4+ cores
- RAM: 8GB minimum, 16GB recommended
- Disk: 100GB+ SSD
- Network: Static IP, firewall configured

**Software**:
- Elixir 1.18+
- Erlang/OTP 28+
- PostgreSQL 16+
- Nginx (reverse proxy)
- Systemd (process management)

---

## Environment Variables

### Required Variables

Create `/etc/expo-controller/env`:

```bash
# API Authentication
CONTROLLER_API_KEY="production-api-key-minimum-32-characters-very-secure"

# Database
DATABASE_URL="postgresql://expo:password@localhost/expo_controller_prod"

# Phoenix
SECRET_KEY_BASE="generated-via-mix-phx-gen-secret-must-be-64-chars-minimum"
PHX_HOST="controller.example.com"
PORT=4000

# Storage
STORAGE_ROOT="/var/lib/expo-controller/storage"

# Monitoring (optional)
SENTRY_DSN="https://..."
HONEYBADGER_API_KEY="..."

# LiveDashboard (optional, disable in prod)
ENABLE_LIVE_DASHBOARD=false
```

### Generate Secrets

```bash
# Generate SECRET_KEY_BASE
mix phx.gen.secret

# Generate API key
openssl rand -base64 32
```

### Security Best Practices

**Permissions**:
```bash
sudo chmod 600 /etc/expo-controller/env
sudo chown expo-controller:expo-controller /etc/expo-controller/env
```

**Never commit**:
- API keys
- Database passwords
- SECRET_KEY_BASE
- Any credentials

---

## Database Setup

### Install PostgreSQL

```bash
# Ubuntu
sudo apt update
sudo apt install postgresql-16

# Start service
sudo systemctl start postgresql
sudo systemctl enable postgresql
```

### Create Production Database

```bash
# Switch to postgres user
sudo -u postgres psql

# Create user
CREATE USER expo WITH PASSWORD 'secure-password-here';

# Create database
CREATE DATABASE expo_controller_prod OWNER expo;

# Grant privileges
GRANT ALL PRIVILEGES ON DATABASE expo_controller_prod TO expo;

# Exit
\q
```

### Configure PostgreSQL

Edit `/etc/postgresql/16/main/postgresql.conf`:

```conf
# Performance tuning
shared_buffers = 256MB
effective_cache_size = 1GB
work_mem = 16MB
maintenance_work_mem = 128MB
max_connections = 100

# Write-ahead logging
wal_level = replica
max_wal_size = 1GB
min_wal_size = 80MB

# Logging
log_destination = 'stderr'
logging_collector = on
log_directory = '/var/log/postgresql'
log_filename = 'postgresql-%Y-%m-%d_%H%M%S.log'
log_line_prefix = '%m [%p] %q%u@%d '
log_timezone = 'UTC'
```

Edit `/etc/postgresql/16/main/pg_hba.conf`:

```conf
# Local connections
local   expo_controller_prod    expo                                md5
host    expo_controller_prod    expo            127.0.0.1/32        md5
```

**Restart PostgreSQL**:
```bash
sudo systemctl restart postgresql
```

### Run Migrations

```bash
cd /opt/expo-controller
MIX_ENV=prod mix ecto.migrate
```

---

## Build Release

### Compile Production Release

```bash
# On build server or production server
cd packages/controller_elixir

# Set environment
export MIX_ENV=prod

# Fetch dependencies
mix deps.get --only prod

# Compile
mix compile

# Build assets (if any)
mix assets.deploy

# Create release
mix release
```

**Output**: `_build/prod/rel/expo_controller/`

### Release Structure

```
_build/prod/rel/expo_controller/
├── bin/
│   ├── expo_controller        # Start script
│   └── expo_controller.bat    # Windows start script
├── lib/
│   └── expo_controller-*.ez   # Compiled application
├── releases/
│   └── 0.1.0/
│       ├── env.sh             # Environment setup
│       └── start_erl.data     # OTP boot data
└── erts-*/                    # Embedded Erlang runtime
```

### Deploy Release

**Copy to production**:
```bash
# Build on local machine
mix release

# Package
tar -czf expo_controller.tar.gz _build/prod/rel/expo_controller

# Transfer to production
scp expo_controller.tar.gz user@production-server:/tmp/

# On production server
sudo mkdir -p /opt/expo-controller
sudo tar -xzf /tmp/expo_controller.tar.gz -C /opt/expo-controller
sudo chown -R expo-controller:expo-controller /opt/expo-controller
```

---

## Systemd Service

### Create Service File

**File**: `/etc/systemd/system/expo-controller.service`

```ini
[Unit]
Description=Expo Free Agent Controller (Elixir)
After=network.target postgresql.service
Requires=postgresql.service

[Service]
Type=forking
User=expo-controller
Group=expo-controller
WorkingDirectory=/opt/expo-controller
EnvironmentFile=/etc/expo-controller/env

# Start command
ExecStart=/opt/expo-controller/bin/expo_controller start

# Stop command
ExecStop=/opt/expo-controller/bin/expo_controller stop

# Restart behavior
Restart=on-failure
RestartSec=10
KillMode=process

# Resource limits
LimitNOFILE=65536
LimitNPROC=4096

# Security
PrivateTmp=true
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
```

### Create User

```bash
sudo useradd -r -s /bin/false expo-controller
sudo mkdir -p /var/lib/expo-controller/storage
sudo chown -R expo-controller:expo-controller /var/lib/expo-controller
```

### Enable and Start

```bash
# Reload systemd
sudo systemctl daemon-reload

# Enable on boot
sudo systemctl enable expo-controller

# Start service
sudo systemctl start expo-controller

# Check status
sudo systemctl status expo-controller

# View logs
sudo journalctl -u expo-controller -f
```

---

## Nginx Reverse Proxy

### Install Nginx

```bash
sudo apt install nginx
```

### Configure Nginx

**File**: `/etc/nginx/sites-available/expo-controller`

```nginx
upstream phoenix {
    server 127.0.0.1:4000;
    keepalive 32;
}

server {
    listen 80;
    server_name controller.example.com;

    # Redirect to HTTPS
    return 301 https://$server_name$request_uri;
}

server {
    listen 443 ssl http2;
    server_name controller.example.com;

    # SSL configuration
    ssl_certificate /etc/letsencrypt/live/controller.example.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/controller.example.com/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers on;

    # Logging
    access_log /var/log/nginx/expo-controller-access.log;
    error_log /var/log/nginx/expo-controller-error.log;

    # File upload limits
    client_max_body_size 1G;
    client_body_timeout 600s;

    # Proxy settings
    proxy_http_version 1.1;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;

    # API endpoints
    location / {
        proxy_pass http://phoenix;
        proxy_redirect off;
        proxy_read_timeout 600s;
        proxy_send_timeout 600s;
    }

    # WebSocket support (for LiveView/Channels)
    location /socket {
        proxy_pass http://phoenix;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
    }

    # Health check (no auth required)
    location /health {
        proxy_pass http://phoenix;
        access_log off;
    }

    # Static files (if needed)
    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg)$ {
        proxy_pass http://phoenix;
        expires 1y;
        add_header Cache-Control "public, immutable";
    }
}
```

### Enable Site

```bash
# Create symlink
sudo ln -s /etc/nginx/sites-available/expo-controller /etc/nginx/sites-enabled/

# Test configuration
sudo nginx -t

# Reload Nginx
sudo systemctl reload nginx
```

### SSL Certificate (Let's Encrypt)

```bash
# Install certbot
sudo apt install certbot python3-certbot-nginx

# Obtain certificate
sudo certbot --nginx -d controller.example.com

# Auto-renewal (already configured by certbot)
sudo systemctl status certbot.timer
```

---

## Health Check Endpoint

### Implement Health Check

**File**: `lib/expo_controller_web/controllers/health_controller.ex`

```elixir
defmodule ExpoControllerWeb.HealthController do
  use ExpoControllerWeb, :controller

  def index(conn, _params) do
    # Check database connectivity
    db_status = case Repo.query("SELECT 1") do
      {:ok, _} -> "healthy"
      {:error, _} -> "unhealthy"
    end

    # Check GenServers
    queue_status = if Process.whereis(QueueManager), do: "healthy", else: "unhealthy"
    heartbeat_status = if Process.whereis(HeartbeatMonitor), do: "healthy", else: "unhealthy"

    status = if db_status == "healthy" and queue_status == "healthy" and heartbeat_status == "healthy" do
      :ok
    else
      :service_unavailable
    end

    conn
    |> put_status(status)
    |> json(%{
      status: to_string(status),
      database: db_status,
      queue_manager: queue_status,
      heartbeat_monitor: heartbeat_status,
      timestamp: DateTime.utc_now()
    })
  end
end
```

**Add route** (`lib/expo_controller_web/router.ex`):
```elixir
scope "/", ExpoControllerWeb do
  get "/health", HealthController, :index
end
```

### Monitor Health

```bash
# Check health
curl https://controller.example.com/health

# Expected response
{
  "status": "ok",
  "database": "healthy",
  "queue_manager": "healthy",
  "heartbeat_monitor": "healthy",
  "timestamp": "2024-01-28T12:00:00Z"
}
```

---

## Monitoring and Observability

### Application Metrics

**Install Telemetry**:
Already included in Phoenix.

**Export to Prometheus** (optional):
```elixir
# mix.exs
{:telemetry_metrics_prometheus, "~> 1.1"}

# lib/expo_controller_web/telemetry.ex
defmodule ExpoControllerWeb.Telemetry do
  use Supervisor
  import Telemetry.Metrics

  def start_link(arg) do
    Supervisor.start_link(__MODULE__, arg, name: __MODULE__)
  end

  def init(_arg) do
    children = [
      {:telemetry_poller, measurements: periodic_measurements(), period: 10_000},
      {TelemetryMetricsPrometheus, metrics: metrics()}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  defp metrics do
    [
      # Phoenix metrics
      summary("phoenix.endpoint.stop.duration",
        unit: {:native, :millisecond}
      ),
      summary("phoenix.router_dispatch.stop.duration",
        unit: {:native, :millisecond}
      ),

      # Database metrics
      summary("expo_controller.repo.query.total_time",
        unit: {:native, :millisecond}
      ),

      # Custom metrics
      counter("expo_controller.builds.created.count"),
      counter("expo_controller.builds.completed.count"),
      counter("expo_controller.builds.failed.count"),
      last_value("expo_controller.queue.pending.count")
    ]
  end
end
```

**Prometheus scrape endpoint**: `http://localhost:4000/metrics`

### Log Aggregation

**Structured JSON logging** (`config/prod.exs`):
```elixir
config :logger, :console,
  format: {Jason, :encode!},
  metadata: [:request_id, :module, :function]
```

**Forward logs to centralized system**:
- Syslog
- Logstash
- CloudWatch Logs
- Datadog

**Example** (Syslog):
```elixir
# mix.exs
{:logger_json, "~> 5.1"}
{:syslog, "~> 1.1"}

# config/prod.exs
config :logger,
  backends: [:console, Syslog]

config :logger, Syslog,
  appid: "expo_controller",
  facility: :local0,
  level: :info
```

### Error Tracking

**Sentry Integration**:
```elixir
# mix.exs
{:sentry, "~> 10.0"}

# config/prod.exs
config :sentry,
  dsn: System.get_env("SENTRY_DSN"),
  environment_name: :prod,
  enable_source_code_context: true,
  root_source_code_path: File.cwd!(),
  tags: %{
    env: "production"
  }

# lib/expo_controller_web/endpoint.ex
plug Sentry.PlugContext
```

---

## Backup and Disaster Recovery

### Database Backups

**Automated PostgreSQL backups**:

```bash
#!/bin/bash
# /usr/local/bin/backup-expo-controller.sh

BACKUP_DIR=/var/backups/expo-controller
DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE=$BACKUP_DIR/expo_controller_$DATE.sql.gz

mkdir -p $BACKUP_DIR

# Dump database
pg_dump -U expo expo_controller_prod | gzip > $BACKUP_FILE

# Verify backup
gunzip -t $BACKUP_FILE
if [ $? -eq 0 ]; then
    echo "Backup successful: $BACKUP_FILE"
else
    echo "Backup failed!"
    exit 1
fi

# Cleanup old backups (keep 30 days)
find $BACKUP_DIR -name "expo_controller_*.sql.gz" -mtime +30 -delete

# Upload to S3 (optional)
# aws s3 cp $BACKUP_FILE s3://backups/expo-controller/
```

**Cron job**:
```cron
# Daily backup at 2 AM
0 2 * * * /usr/local/bin/backup-expo-controller.sh
```

### File Storage Backups

```bash
# Backup storage directory
rsync -avz /var/lib/expo-controller/storage/ backup-server:/backups/expo-controller/storage/

# Or use S3
aws s3 sync /var/lib/expo-controller/storage/ s3://expo-controller-storage/
```

### Restore Procedure

**Database**:
```bash
# Stop service
sudo systemctl stop expo-controller

# Drop existing database
sudo -u postgres psql -c "DROP DATABASE expo_controller_prod;"

# Recreate database
sudo -u postgres psql -c "CREATE DATABASE expo_controller_prod OWNER expo;"

# Restore backup
gunzip -c /var/backups/expo-controller/expo_controller_20240128.sql.gz | \
  sudo -u postgres psql expo_controller_prod

# Start service
sudo systemctl start expo-controller
```

---

## Blue-Green Deployment

### Strategy

1. **Current** (Blue): Running production
2. **New** (Green): Deploy new version alongside
3. **Test**: Validate green environment
4. **Switch**: Route traffic to green
5. **Monitor**: Watch for issues
6. **Rollback**: Switch back to blue if needed

### Implementation

**Run both versions**:
```bash
# Blue (current)
/opt/expo-controller-blue/bin/expo_controller start
# Listening on port 4000

# Green (new)
PORT=4001 /opt/expo-controller-green/bin/expo_controller start
# Listening on port 4001
```

**Nginx config**:
```nginx
upstream phoenix_blue {
    server 127.0.0.1:4000;
}

upstream phoenix_green {
    server 127.0.0.1:4001;
}

server {
    # ...

    location / {
        # Switch upstream to cut over
        proxy_pass http://phoenix_blue;  # Change to phoenix_green
    }
}
```

**Cutover**:
```bash
# Update Nginx config (blue → green)
sudo sed -i 's/phoenix_blue/phoenix_green/g' /etc/nginx/sites-available/expo-controller

# Reload Nginx
sudo nginx -s reload

# Monitor for errors
sudo journalctl -u expo-controller -f

# If issues, rollback
sudo sed -i 's/phoenix_green/phoenix_blue/g' /etc/nginx/sites-available/expo-controller
sudo nginx -s reload
```

---

## Performance Tuning

### BEAM VM Settings

**Configure via environment** (`/etc/expo-controller/env`):
```bash
# Scheduler threads (1 per CPU core)
ELIXIR_ERL_OPTIONS="+S 4:4"

# Async thread pool (for file I/O)
ELIXIR_ERL_OPTIONS="${ELIXIR_ERL_OPTIONS} +A 32"

# Process limit
ELIXIR_ERL_OPTIONS="${ELIXIR_ERL_OPTIONS} +P 1048576"

# Memory allocator tuning
ELIXIR_ERL_OPTIONS="${ELIXIR_ERL_OPTIONS} +MBas aobf"
```

### Database Connection Pool

```elixir
# config/prod.exs
config :expo_controller, ExpoController.Repo,
  pool_size: 20,  # Increase for high load
  queue_target: 50,
  queue_interval: 1000
```

### File Upload Limits

```elixir
# config/prod.exs
config :expo_controller, ExpoControllerWeb.Endpoint,
  http: [
    port: 4000,
    protocol_options: [
      max_request_line_length: 8192,
      max_header_value_length: 8192
    ]
  ]

config :phoenix, :json_library, Jason

# Plug.Parsers (for multipart uploads)
plug Plug.Parsers,
  parsers: [:multipart],
  pass: ["*/*"],
  length: 1_000_000_000  # 1GB max
```

---

## Troubleshooting

### Service Won't Start

**Check logs**:
```bash
sudo journalctl -u expo-controller -n 50
```

**Common issues**:
- Port already in use
- Database connection failed
- Missing environment variables
- Permission errors

### High Memory Usage

**Check BEAM memory**:
```bash
# Connect to running node
/opt/expo-controller/bin/expo_controller remote

# Inspect memory
:erlang.memory()
:observer.start()  # GUI (requires X11 forwarding)
```

**Garbage collection**:
```elixir
# Force GC on all processes
for pid <- Process.list(), do: :erlang.garbage_collect(pid)
```

### Database Connection Pool Exhausted

**Symptoms**: Timeout errors, slow responses

**Check connections**:
```sql
SELECT count(*) FROM pg_stat_activity WHERE datname = 'expo_controller_prod';
```

**Increase pool size** (`config/prod.exs`):
```elixir
config :expo_controller, ExpoController.Repo,
  pool_size: 30  # Increase from 20
```

---

## Resources

- [Phoenix Deployment Guide](https://hexdocs.pm/phoenix/deployment.html)
- [Mix Release Documentation](https://hexdocs.pm/mix/Mix.Tasks.Release.html)
- [PostgreSQL Performance Tuning](https://wiki.postgresql.org/wiki/Performance_Optimization)
- [BEAM VM Tuning](https://www.erlang.org/doc/man/erl.html)
- [Nginx Configuration](https://nginx.org/en/docs/)

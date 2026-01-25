# Expo Free Agent Controller - CapRover Deployment

## Prerequisites

- CapRover instance running and accessible
- CapRover CLI installed: `npm install -g caprover`
- Domain name configured for your CapRover instance

## Quick Deploy to CapRover

### 1. Login to CapRover

```bash
caprover login
```

### 2. Create App

In CapRover dashboard:
1. Go to Apps
2. Create new app: `expo-controller` (or your preferred name)
3. Enable HTTPS (recommended)

### 3. Configure Environment Variables

In the app settings, add these environment variables:

```
CONTROLLER_API_KEY=your-secure-random-api-key-here
CONTROLLER_URL=https://expo-controller.your-domain.com
PORT=3000
NODE_ENV=production
```

**Important:** Generate a strong random API key:
```bash
openssl rand -base64 32
```

### 4. Configure Persistent Storage

Add persistent directories in CapRover app settings:
- Path in App: `/app/data`
- Label: `controller-data`

- Path in App: `/app/storage`
- Label: `controller-storage`

### 5. Deploy

From this directory:

```bash
caprover deploy
```

When prompted:
- Select your CapRover instance
- Select the `expo-controller` app
- Confirm deployment

### 6. Verify Deployment

Check the app logs in CapRover dashboard. You should see:

```
Controller server starting...
✓ Server running on port 3000
```

Test the API:

```bash
curl -H "X-API-Key: your-api-key" https://expo-controller.your-domain.com/api/builds
```

## Environment Variables Reference

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `CONTROLLER_API_KEY` | Yes | - | API key for authentication |
| `CONTROLLER_URL` | Yes | - | Public URL of controller |
| `PORT` | No | 3000 | Server port |
| `NODE_ENV` | No | production | Runtime environment |
| `MAX_SOURCE_SIZE_MB` | No | 500 | Max source file size |
| `MAX_CERTS_SIZE_MB` | No | 50 | Max certs file size |
| `MAX_RESULT_SIZE_MB` | No | 1000 | Max result file size |

## Post-Deployment Configuration

### Update CLI Configuration

Tell CLI to use your deployed controller:

```bash
export EXPO_CONTROLLER_URL=https://expo-controller.your-domain.com
export EXPO_CONTROLLER_API_KEY=your-api-key
```

Or add to `~/.bashrc` / `~/.zshrc`:

```bash
echo 'export EXPO_CONTROLLER_URL=https://expo-controller.your-domain.com' >> ~/.zshrc
echo 'export EXPO_CONTROLLER_API_KEY=your-api-key' >> ~/.zshrc
```

### Configure Workers

Update worker configuration to point to deployed controller:

```bash
# On macOS worker
defaults write com.expo.FreeAgent controllerURL "https://expo-controller.your-domain.com"
defaults write com.expo.FreeAgent apiKey "your-api-key"
```

## Troubleshooting

### Logs

View logs in CapRover dashboard or via CLI:

```bash
caprover logs -a expo-controller -n 100
```

### Common Issues

**Database not persisting:**
- Verify persistent storage is configured in CapRover
- Check `/app/data` directory is mounted

**Workers can't connect:**
- Verify `CONTROLLER_URL` matches your actual domain
- Check HTTPS is enabled and certificate is valid
- Verify firewall allows inbound connections on port 443

**Build uploads failing:**
- Check `MAX_SOURCE_SIZE_MB` environment variable
- Verify CapRover's nginx max body size (default 100M)
- May need to increase in CapRover settings

### Increase Upload Size Limit

If builds are larger than 100MB, update CapRover nginx config:

1. Go to CapRover Settings → Nginx Config
2. Add to `http` block:
```nginx
client_max_body_size 1G;
```
3. Save and restart CapRover

## Monitoring

### Health Check Endpoint

CapRover will automatically monitor the app. You can also set up custom health checks:

Add in app settings:
- Health Check Path: `/api/builds`
- Method: GET
- Headers: `X-API-Key: your-api-key`

### Database Backup

Set up periodic backups of `/app/data/builds.db`:

```bash
# On CapRover host
docker exec -it $(docker ps -qf "name=expo-controller") sqlite3 /app/data/builds.db ".backup /app/data/backup.db"
docker cp $(docker ps -qf "name=expo-controller"):/app/data/backup.db ./backup-$(date +%Y%m%d).db
```

## Scaling

CapRover supports horizontal scaling, but this controller uses SQLite which doesn't support multiple instances. For production scaling:

1. Migrate to PostgreSQL (planned feature)
2. Use CapRover's load balancer
3. Run multiple controller instances

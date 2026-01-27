# CapRover Deployment - Quick Reference

## First Time Setup

```bash
# 1. Install CapRover CLI globally
npm install -g caprover

# 2. Login to your CapRover instance
caprover login

# 3. Create app in CapRover dashboard
# - App name: expo-controller (or your choice)
# - Enable HTTPS
# - Add persistent storage: /app/data and /app/storage

# 4. Set environment variables in CapRover dashboard
# - CONTROLLER_API_KEY (generate with: openssl rand -base64 32)
# - CONTROLLER_URL (e.g., https://expo-controller.yourdomain.com)
# - PORT=3000
# - NODE_ENV=production
```

## Deploy Commands

```bash
# Interactive deployment (prompts for app selection)
bun run deploy

# Deploy to specific app
bun run deploy:app expo-controller

# Show help
bun run deploy --help
```

## After Deployment

```bash
# View logs
caprover logs -a expo-controller -n 100

# Test API
curl -H "X-API-Key: your-api-key" https://expo-controller.yourdomain.com/health
```

## Troubleshooting

- **"caprover not found"**: Install with `npm install -g caprover`
- **"not logged in"**: Run `caprover login`
- **Upload size errors**: Increase nginx body size in CapRover settings
- **Database not persisting**: Check persistent storage is configured

See [DEPLOYMENT.md](./DEPLOYMENT.md) for full documentation.

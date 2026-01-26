# Cloudflare Pages Deployment Guide

## Prerequisites

- Cloudflare account
- GitHub repo connected to Cloudflare
- Wrangler CLI (installed as dev dependency)

## Deployment Options

### Option 1: Cloudflare Dashboard (Recommended for first deploy)

1. **Connect Repository:**
   - Go to [Cloudflare Dashboard](https://dash.cloudflare.com/) → Pages
   - Click "Create a project" → "Connect to Git"
   - Select your GitHub repo: `expo-free-agent`
   - Grant access

2. **Configure Build Settings:**
   ```
   Project name: expo-free-agent
   Production branch: main
   Build command: cd packages/landing-page && bun run build
   Build output directory: packages/landing-page/dist
   Root directory: /
   Framework preset: None
   ```

3. **Environment Variables (Optional):**
   - None required for static site
   - Add if you need API URLs in the future

4. **Deploy:**
   - Click "Save and Deploy"
   - First build takes ~2-3 minutes
   - Site will be live at: `https://expo-free-agent.pages.dev`

5. **Custom Domain (Optional):**
   - Pages → Your Project → Custom domains
   - Add: `expo-free-agent.com`
   - Follow DNS instructions

### Option 2: Wrangler CLI (For quick updates)

**First-time setup:**
```bash
# Login to Cloudflare
cd packages/landing-page
npx wrangler login
```

**Deploy:**
```bash
# From project root
bun run landing-page:deploy

# Or from landing-page directory
cd packages/landing-page
bun run deploy
```

**Manual deploy:**
```bash
cd packages/landing-page
bun run build
npx wrangler pages deploy dist --project-name=expo-free-agent
```

## Automatic Deployments

After initial setup via Dashboard:
- **Every push to `main`** triggers production deployment
- **Pull requests** get preview deployments with unique URLs
- **Preview URL format:** `https://[hash].expo-free-agent.pages.dev`

## Configuration

Build settings in `wrangler.toml`:
```toml
name = "expo-free-agent"
pages_build_output_dir = "dist"

[build]
command = "bun run build"
```

## Troubleshooting

**Build fails:**
- Check build command is correct: `cd packages/landing-page && bun run build`
- Verify output directory: `packages/landing-page/dist`
- Check Cloudflare build logs in Dashboard

**Site not updating:**
- Purge cache: Dashboard → Caching → Purge Everything
- Wait 30-60s for CDN propagation
- Check deployment succeeded in Pages dashboard

**Custom domain not working:**
- Verify DNS records propagated (use `dig your-domain.com`)
- Wait up to 24h for DNS propagation
- Check SSL certificate provisioned (automatic, takes ~5 min)

## Performance

Cloudflare Pages includes:
- ✅ Global CDN (275+ locations)
- ✅ Automatic HTTPS
- ✅ Unlimited bandwidth
- ✅ DDoS protection
- ✅ Free tier: Unlimited static requests

## URLs

- **Production:** `https://expo-free-agent.pages.dev`
- **Custom domain:** `https://expo-free-agent.com` (after setup)
- **PR previews:** `https://[hash].expo-free-agent.pages.dev`

## CI/CD Integration

Already configured:
- GitHub integration for auto-deploy
- Branch previews for PRs
- Build logs in Cloudflare Dashboard

No additional CI/CD needed - Cloudflare handles everything.

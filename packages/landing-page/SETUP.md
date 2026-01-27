# Setup Guide

This landing page is built with Vite, React 19, React Compiler, and Tailwind CSS v4.

## Development

### Start Dev Server

```bash
bun run dev
```

The site will be available at http://localhost:5173

### Build for Production

```bash
bun run build
```

Output is in the `dist/` directory.

### Preview Production Build

```bash
bun run preview
```

## Deployment

### Vercel

```bash
# Install Vercel CLI
bun add -g vercel

# Deploy
vercel
```

### Netlify

```bash
# Install Netlify CLI
bun add -g netlify-cli

# Deploy
netlify deploy --prod
```

### Static Hosting

The `dist/` folder contains static files that can be deployed to:
- GitHub Pages
- Cloudflare Pages
- AWS S3 + CloudFront
- Any static hosting provider

## Customization

### Colors

Edit `src/styles/globals.css` to customize the color scheme:

```css
@theme {
  --color-brand: #6366f1;
  --color-brand-light: #818cf8;
  --color-brand-dark: #4f46e5;
}
```

### Content

All content is in `src/App.tsx`. The components are organized as:

- **Navigation** - Top bar with links
- **Hero Section** - Main headline and CTA
- **Features** - Grid of feature cards
- **How It Works** - Process explanation
- **Get Started** - Setup commands
- **Footer** - Links and credits

### Animations

Custom animations are defined in `src/styles/globals.css`:

- `animate-fade-in` - Fade in from bottom
- `animate-float` - Floating animation
- `gradient-text` - Animated gradient text
- `glow` - Glow effect

## Tech Details

### React Compiler

The React Compiler is enabled in `vite.config.ts`. It automatically optimizes components for better performance.

### Tailwind CSS v4

Uses the new `@theme` directive for custom design tokens. No separate tailwind.config.js needed.

### Type Safety

Full TypeScript support with strict mode enabled. Run type checking:

```bash
tsc --noEmit
```

## Performance

The production build is optimized with:
- Code splitting
- Tree shaking
- Minification
- Gzip compression

Target metrics:
- **First Contentful Paint:** < 1s
- **Time to Interactive:** < 2s
- **Total Bundle Size:** < 250KB gzipped

## Browser Support

- Chrome/Edge (last 2 versions)
- Firefox (last 2 versions)
- Safari (last 2 versions)
- iOS Safari (last 2 versions)

Modern features used:
- CSS Grid
- Flexbox
- CSS Custom Properties
- Backdrop Filter
- Gradient Backgrounds

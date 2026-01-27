# Free Agent Landing Page

> Earn free Expo builds by sharing your Mac's idle CPU

A clean, professional landing page for Expo Free Agent — designed to match the Expo ecosystem aesthetic.

## Design Philosophy

This landing page follows [Expo.dev](https://expo.dev)'s design principles:

- ✅ **Clean white backgrounds** with high-contrast text
- ✅ **Bold typography** with clear hierarchy
- ✅ **Minimal color palette** (blue accents on white/gray)
- ✅ **Professional, not flashy** — clarity over complexity
- ✅ **Generous whitespace** and breathing room
- ✅ **Simple, elegant interactions**

See [EXPO-DESIGN.md](./EXPO-DESIGN.md) for the complete design system.

## Tech Stack

- **Vite** — Fast build tool
- **React 19** with React Compiler enabled
- **Tailwind CSS v4** — Utility-first styling
- **TypeScript** — Type safety

## Development

```bash
# Install dependencies
bun install

# Start dev server
bun run dev
# → http://localhost:5173

# Build for production
bun run build

# Preview production build
bun run preview
```

## Key Features

### 🌓 Dark/Light Mode
- **Dark mode (default)** — Beautiful dark theme with high contrast
- **Light mode** — Clean, professional light theme
- **Smart toggle** — Moon/sun icon in top-right nav
- **Persistent** — Saves preference to localStorage
- **System-aware** — Respects `prefers-color-scheme` on first load
- **Smooth transitions** — 300ms animated color changes

See [DARK-MODE.md](./DARK-MODE.md) for implementation details.

### Hero Section
- Clear value proposition: "Earn Free Expo Builds"
- Explains the credit system immediately
- Clean CTAs (Get Started + GitHub)

### 4-Step Flow
- Visual representation of the earn/spend cycle
- Numbered badges for clarity
- Minimal, professional design

### Features Grid
- 6 key features in 3-column grid
- Hover effects with blue accent
- Icon + Title + Description pattern

### Architecture Section (Dark)
- Single dark section for visual contrast
- 3 components explained clearly
- Blue callout box with key value prop

### Get Started
- 3 command blocks with real terminal styling
- Step-by-step instructions
- Link to full documentation

## Color Palette

```
Primary:   #2563eb (blue-600)
Dark:      #111827 (gray-900)
Text:      #6b7280 (gray-600)
Border:    #e5e7eb (gray-200)
Background: #ffffff (white)
```

## Content Focus

**Value Proposition:**
- Share Mac's idle CPU → Earn credits
- 1 build processed = 1 build credit
- Spend credits on your own builds
- Fair, transparent, self-hosted

**Target Audience:**
- Expo developers
- Mac owners with idle compute
- Teams wanting cost-effective builds
- Open source contributors

## Accessibility

- ✅ WCAG AAA contrast ratios
- ✅ Semantic HTML structure
- ✅ Keyboard navigation
- ✅ Mobile responsive
- ✅ Screen reader friendly

## Build Output

```
dist/index.html           1.33 kB  (gzipped: 0.56 kB)
dist/assets/index.css    24.93 kB  (gzipped: 5.24 kB)
dist/assets/index.js    207.60 kB  (gzipped: 64.60 kB)
Build time: ~580ms
```

## Project Structure

```
src/
├── App.tsx                    # Main component with all sections
├── main.tsx                   # Entry point with ThemeProvider
├── components/
│   └── ThemeToggle.tsx       # Dark/light mode toggle button
├── hooks/
│   └── useTheme.tsx          # Theme state management
└── styles/
    └── globals.css           # Tailwind + custom styles + theme variants

dist/                         # Production build output
```

## Design Iterations

1. **v1**: Dark theme with heavy gradients (rejected)
2. **v2**: High contrast dark theme (rejected)
3. **v3**: Expo-inspired clean white design ✅

The final design matches Expo's aesthetic: professional, clean, and focused on content clarity.

## License

MIT — Part of the Expo ecosystem

---

Built with ❤️ for the Expo community

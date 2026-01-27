# Design System Reference

## 🎨 Color Palette

### Brand Colors
```css
--color-brand: #6366f1        /* Indigo 500 */
--color-brand-light: #818cf8  /* Indigo 400 */
--color-brand-dark: #4f46e5   /* Indigo 600 */
```

### Gradients
```css
/* Primary brand gradient */
linear-gradient(to bottom right, #6366f1, #a855f7, #ec4899)
/* Indigo → Purple → Pink */

/* Secondary gradient (orbs) */
linear-gradient(to bottom right, #a855f7, #ec4899)
/* Purple → Pink */
```

### Gray Scale
```css
zinc-50:  #fafafa
zinc-100: #f5f5f5
zinc-200: #e5e5e5
zinc-300: #d4d4d4
zinc-400: #a3a3a3
zinc-500: #737373
zinc-600: #525252
zinc-700: #404040
zinc-800: #262626
zinc-900: #171717
zinc-950: #0a0a0a  /* Background */
```

## 📐 Spacing Scale

```
0.5 = 2px
1   = 4px
2   = 8px
3   = 12px
4   = 16px
6   = 24px
8   = 32px
12  = 48px
16  = 64px
20  = 80px
```

## 🔤 Typography

### Font Family
```css
font-sans: system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif
```

### Font Sizes
```css
text-sm:  14px
text-base: 16px
text-lg:  18px
text-xl:  20px
text-2xl: 24px
text-4xl: 36px
text-5xl: 48px
text-6xl: 60px
text-8xl: 96px
```

### Font Weights
```css
font-medium:  500
font-semibold: 600
font-bold:    700
```

## 🎭 Effects

### Border Radius
```css
rounded-lg:   8px
rounded-xl:   12px
rounded-2xl:  16px
rounded-full: 9999px
```

### Opacity
```css
/80  = 80%  (navigation backdrop)
/50  = 50%  (borders, backgrounds)
/30  = 30%  (background sections)
/20  = 20%  (gradient orbs)
```

### Blur
```css
blur-3xl:      48px  (gradient orbs)
backdrop-blur: 12px  (navigation)
```

### Shadows & Glows
```css
.glow {
  box-shadow: 0 0 30px rgba(99, 102, 241, 0.3);
}
```

## 🎬 Animations

### Timing Functions
```css
ease-out:    cubic-bezier(0, 0, 0.2, 1)
ease-in-out: cubic-bezier(0.4, 0, 0.2, 1)
```

### Durations
```css
transition-colors: 300ms
transition-all:    300ms
animate-float:     3000ms
animate-fade-in:   800ms
animate-ping:      1000ms
```

### Keyframes

**fade-in:**
```css
from: opacity(0) translateY(20px)
to:   opacity(1) translateY(0)
```

**float:**
```css
0%, 100%: translateY(0)
50%:      translateY(-10px)
```

## 📱 Breakpoints

```css
sm:  640px   /* Small tablets */
md:  768px   /* Tablets */
lg:  1024px  /* Laptops */
xl:  1280px  /* Desktops */
2xl: 1536px  /* Large displays */
```

## 🎯 Component Patterns

### Card Style
```css
background:   zinc-900/50
border:       1px solid zinc-800/50
border-radius: 16px (rounded-2xl)
padding:      24px (p-6)

hover:
  border-color: zinc-700/50
  scale:        1.02
```

### Button Primary
```css
background:   indigo-600
hover:        indigo-500
padding:      16px 32px (py-4 px-8)
border-radius: 12px (rounded-xl)
shadow:       glow effect
```

### Button Secondary
```css
background:   zinc-800
hover:        zinc-700
padding:      16px 32px
border-radius: 12px
```

## 🌈 Gradient Utilities

### .gradient-text
```css
background: linear-gradient(to bottom right, zinc-50, zinc-100, zinc-400)
-webkit-background-clip: text
-webkit-text-fill-color: transparent
```

### .gradient-brand
```css
background: linear-gradient(to bottom right, indigo-500, purple-500, pink-500)
```

## 🎨 Color Usage Guide

### Text Colors
- Primary text:     `text-zinc-100`
- Secondary text:   `text-zinc-400`
- Muted text:       `text-zinc-500`
- Interactive:      `text-indigo-400`
- Interactive hover: `text-indigo-300`

### Background Colors
- Page background:   `bg-zinc-950`
- Card background:   `bg-zinc-900/50`
- Section background: `bg-zinc-900/30`
- Button primary:    `bg-indigo-600`
- Button secondary:  `bg-zinc-800`

### Border Colors
- Default:  `border-zinc-800/50`
- Hover:    `border-zinc-700/50`
- Accent:   `border-indigo-500/20`

## 📊 Layout Grid

### Container
```css
max-width: 1280px (max-w-7xl)
padding-x: 24px on mobile, 32px on desktop
margin:    0 auto
```

### Feature Grid
```css
grid-template-columns: 
  1 column on mobile
  2 columns on md
  3 columns on lg
gap: 24px
```

## ✨ Special Effects

### Floating Orbs
- Size: 384px (w-96 h-96)
- Blur: 48px (blur-3xl)
- Opacity: 20% (opacity-20)
- Animation: float 3s ease-in-out infinite

### Glassmorphism (Navigation)
- Background: zinc-950 at 80% opacity
- Backdrop filter: blur(12px)
- Border bottom: 1px solid zinc-800/50

### Glow Effects
- Used on: Brand elements, CTAs, step numbers
- Shadow: 0 0 30px rgba(99, 102, 241, 0.3)

## 🎯 Accessibility

### Color Contrast
All text meets WCAG AA standards:
- White on zinc-950: ✅ AAA
- zinc-400 on zinc-950: ✅ AA
- indigo-400 on zinc-950: ✅ AA

### Focus States
All interactive elements have visible focus states via browser defaults

### Semantic HTML
- Proper heading hierarchy (h1 → h2 → h3)
- Semantic nav, section, footer elements
- Descriptive link text

## 🎨 Design Principles Applied

1. **No hard borders** - All borders use soft opacity (50%)
2. **Consistent spacing** - Uses 4px base grid
3. **Visual hierarchy** - Clear size/weight/color progression
4. **Subtle motion** - Smooth transitions, gentle animations
5. **Dark theme** - Professional, modern aesthetic
6. **Brand consistency** - Indigo gradient used throughout

---

This design system creates a **cohesive, professional, high-end SaaS aesthetic** that's easy to maintain and extend.

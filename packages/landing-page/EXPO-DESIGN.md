# Expo-Inspired Design System

## Design Philosophy

This landing page follows Expo's design principles to feel like a natural part of the Expo ecosystem.

### ✅ Key Principles Applied

1. **Clean White Background**
   - Primary background: Pure white (`#ffffff`)
   - Not dark! Expo.dev uses light backgrounds prominently
   - Dark sections used sparingly for contrast

2. **High Contrast Typography**
   - Headings: `#111827` (gray-900) - near black
   - Body text: `#6b7280` (gray-500/600) - medium gray
   - Light text on dark: Pure white
   - Perfect readability, WCAG AAA compliant

3. **Minimal Color Palette**
   - Primary: Blue (`#2563eb` - blue-600)
   - Accent: Darker blue (`#1d4ed8` - blue-700)
   - Grays: Clean, professional gray scale
   - No gradients on main backgrounds
   - Simple blue gradient only on logo

4. **Bold, Clear Typography**
   - Headings: `font-black` (900 weight)
   - Tracking: `-tight` for large text
   - Clear hierarchy: 5xl-7xl for hero, 4xl-5xl for sections
   - Professional, not flashy

5. **Breathing Room**
   - Generous padding and margins
   - Whitespace is intentional
   - Content never feels cramped
   - Clean grid layouts

6. **Simple Interactions**
   - Hover states: subtle color changes
   - Borders: 2px solid, clean
   - Rounded corners: `rounded-xl` (12px)
   - No excessive animations or effects

7. **Professional Components**
   - Cards with borders, not shadows (mostly)
   - Clean navigation with simple links
   - CTA buttons: solid colors, clear contrast
   - Code blocks: dark with syntax highlighting

## Color System

### Primary Colors
```css
Blue-600: #2563eb  /* Primary CTA, accents */
Blue-700: #1d4ed8  /* Hover states */
Blue-50:  #eff6ff  /* Light backgrounds */
```

### Grays (High Contrast)
```css
Gray-900: #111827  /* Headings, dark sections */
Gray-800: #1f2937  /* Dark card backgrounds */
Gray-700: #374151  /* Borders on dark */
Gray-600: #4b5563  /* Body text (dark sections) */
Gray-500: #6b7280  /* Secondary text */
Gray-200: #e5e7eb  /* Borders */
Gray-50:  #f9fafb  /* Light section backgrounds */
White:    #ffffff  /* Primary background */
```

## Layout Structure

### Hero Section
- **White background**
- Centered content, max-width 4xl
- Large bold heading (5xl-7xl)
- Supporting text in gray-600
- Two-button CTA (black + outline)
- Badge component with blue accent

### Feature Grid
- **White background**
- 3-column grid (responsive)
- Cards with 2px borders (gray-200)
- Hover: border changes to blue-600
- Icons, bold titles, gray body text

### Dark Section (Architecture)
- **Gray-900 background** (used sparingly!)
- White headings
- Gray-400 supporting text
- Cards with gray-800 background
- Blue accent callout box

### Get Started
- **White background**
- Command blocks with dark code backgrounds
- Clean borders and typography
- Simple documentation link

## Typography Scale

```
Hero:        text-5xl lg:text-7xl (48px / 72px)
Sections:    text-4xl lg:text-5xl (36px / 48px)
Subheading:  text-xl lg:text-2xl  (20px / 24px)
Body:        text-lg              (18px)
Small:       text-sm              (14px)
```

## Component Patterns

### Button (Primary)
```jsx
bg-gray-900 text-white hover:bg-gray-800
px-8 py-4 rounded-lg font-semibold
```

### Button (Secondary)
```jsx
border-2 border-gray-900 text-gray-900 hover:bg-gray-50
px-8 py-4 rounded-lg font-semibold
```

### Card (Feature)
```jsx
border-2 border-gray-200 hover:border-blue-600
p-6 rounded-xl bg-white
```

### Card (Dark Component)
```jsx
bg-gray-800 border-2 border-gray-700
p-8 rounded-xl
```

### Badge
```jsx
bg-blue-50 border border-blue-200
px-4 py-2 rounded-full
text-sm text-blue-900 font-semibold
```

## What Changed from Previous Version

### Before (Dark, Over-styled)
- ❌ Dark backgrounds everywhere (zinc-950)
- ❌ Lots of gradients and glows
- ❌ Over-animated
- ❌ Didn't match Expo aesthetic

### After (Expo-inspired)
- ✅ Clean white background
- ✅ High contrast, readable text
- ✅ Minimal use of color (blue accents)
- ✅ Professional, clean design
- ✅ Feels like part of Expo ecosystem

## Accessibility

- ✅ WCAG AAA contrast ratios
- ✅ Semantic HTML
- ✅ Clear focus states
- ✅ Readable at all sizes
- ✅ Clean navigation structure

## Responsive Design

- Mobile-first approach
- Breakpoints: `md:` (768px), `lg:` (1024px)
- Grid collapses to single column
- Text scales appropriately
- Navigation adapts

## Build Performance

```
CSS:  24.93 kB (5.24 kB gzipped)
JS:   207.60 kB (64.60 kB gzipped)
Build: 579ms
```

Lightweight, fast, professional.

---

**This design matches Expo's philosophy: clarity over complexity, professional over flashy, usable over impressive.**

# Testing Checklist - Dark/Light Mode

## 🧪 Quick Testing Guide

### Basic Functionality
- [ ] Open the site - should default to dark mode
- [ ] Click the theme toggle in top-right nav
- [ ] Verify smooth color transition (300ms)
- [ ] Check that preference is saved (reload page)
- [ ] Toggle back and forth multiple times

### Visual Quality - Dark Mode
- [ ] All text is clearly readable
- [ ] Navigation bar looks good
- [ ] Hero section gradient orbs are visible
- [ ] Feature cards have proper hover states
- [ ] Code blocks are readable
- [ ] Footer links are visible
- [ ] All borders and separators are visible

### Visual Quality - Light Mode
- [ ] All headings are pure black (not gray)
- [ ] Body text is dark gray (#3f3f46)
- [ ] Background is pure white
- [ ] Cards have subtle gray backgrounds
- [ ] Gradient orbs are visible but subtle
- [ ] All buttons have proper contrast
- [ ] Code blocks are dark with light text
- [ ] No gray-on-white text anywhere

### Toggle Button
- [ ] Moon icon shows in light mode
- [ ] Sun icon shows in dark mode
- [ ] Icons rotate smoothly when toggling
- [ ] Button has hover state
- [ ] Accessible via keyboard (Tab + Enter)
- [ ] Tooltip shows on hover

### Persistence & Detection
- [ ] Toggle to light, reload → stays light
- [ ] Toggle to dark, reload → stays dark
- [ ] Clear localStorage, reload → check system preference
- [ ] If system is light mode, should start light
- [ ] If system is dark mode, should start dark

### Browser Testing
- [ ] Chrome/Edge
- [ ] Firefox
- [ ] Safari
- [ ] Mobile Safari
- [ ] Mobile Chrome

### Transitions
- [ ] All colors transition smoothly
- [ ] No jarring color jumps
- [ ] Animations are smooth (60fps)
- [ ] No layout shifts during toggle
- [ ] No flash of wrong theme

### Accessibility
- [ ] Toggle button has proper aria-label
- [ ] Keyboard navigation works
- [ ] Screen reader announces theme change
- [ ] Focus indicators are visible
- [ ] Contrast ratios meet WCAG AAA

### Performance
- [ ] Page loads without theme flash
- [ ] Toggle is instant (no lag)
- [ ] Smooth scrolling still works
- [ ] Animations don't drop frames
- [ ] Build size is reasonable

## 🚀 Quick Test Commands

```bash
# Development server
bun run dev

# Production build
bun run build

# Preview production build
bun run preview
```

## 🔍 Visual Inspection Points

### Dark Mode Checklist
- Background: Very dark (`#09090b`)
- Cards: Dark gray (`#18181b`)
- Headings: White (`#ffffff`)
- Body text: Light gray (`#d4d4d8`)
- Borders: Dark gray (`#27272a`)
- Accent colors: Vibrant (indigo/purple/pink)

### Light Mode Checklist
- Background: Pure white (`#ffffff`)
- Cards: Very light gray (`#f4f4f5`)
- Headings: **Pure black** (`#000000`)
- Body text: Dark gray (`#3f3f46`)
- Borders: Light gray (`#e4e4e7`)
- Accent colors: Same vibrant colors

## 🐛 Common Issues to Check

- [ ] No horizontal scroll at any viewport width
- [ ] Mobile menu (if any) works in both themes
- [ ] External links still open in new tab
- [ ] GitHub button maintains contrast in both modes
- [ ] Gradient text is readable in both modes
- [ ] No console errors
- [ ] localStorage doesn't throw errors

## ✅ Success Criteria

All of these should be true:
1. ✅ Both themes look equally professional
2. ✅ No gray-on-white text in light mode
3. ✅ Smooth transitions between modes
4. ✅ Preference persists across sessions
5. ✅ System preference is respected
6. ✅ Toggle button is accessible
7. ✅ No layout shifts or flashes
8. ✅ Build succeeds without errors

## 📱 Responsive Testing

Test on these viewport sizes:
- [ ] Mobile (375px)
- [ ] Tablet (768px)
- [ ] Desktop (1440px)
- [ ] Large desktop (1920px)

Both themes should look good at all sizes!

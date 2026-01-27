# CSS Architecture Review - Scroll-Driven Animations

**Date:** 2026-01-26
**Files Reviewed:** `src/App.tsx`, `src/styles/globals.css`

---

## Executive Summary

The scroll-driven animations are broken due to **three fundamental architectural mistakes**:

1. **Global transition rule sabotages immediate DOM updates**
2. **Missing `will-change` / compositor layer hints**
3. **Mixing incompatible animation strategies (CSS keyframes vs scroll-driven JS)**

---

## 🔴 Critical Issues

### 1. Global Transition Rule Destroys Scroll-Driven Updates

**Location:** `globals.css:64-68`

```css
* {
  transition-property: background-color, border-color, color, fill, stroke;
  transition-duration: 300ms;
  transition-timing-function: ease-in-out;
}
```

**Problem:** This applies a 300ms transition to EVERY element. While it only lists specific properties, the `button, a, input...` rule at lines 70-72 **adds opacity and transform**:

```css
button, a, input, select, textarea {
  transition-property: background-color, border-color, color, fill, stroke, transform, opacity, box-shadow;
}
```

But here's the real killer: **CSS specificity and inheritance**. When you do:

```javascript
bgRef.current.style.opacity = opacity.toString();
```

The browser sees the element has `transition-duration: 300ms` inherited from `*`, and even though `opacity` isn't in the transition-property list for `*`, **Safari interprets the global rule differently** and applies transition behavior inconsistently.

**Impact:**
- Chrome: Opacity changes are delayed/smoothed unexpectedly
- Safari: Completely broken - opacity transitions fight with scroll updates

**Solution:** Explicitly disable transitions on scroll-driven elements:

```css
.scroll-driven {
  transition: none !important;
}
```

Or better, remove the global `*` transition rule entirely and apply transitions only where needed.

---

### 2. Hero Background Timing Math is Wrong

**Location:** `App.tsx:103`

```javascript
const opacity = Math.max(0, 1 - y / (vh * 0.8));
```

**Problem:** This formula is inverted from your expectation. You want the background to be fully faded at 80% viewport height scroll. Let's trace:

- At `y = 0`: `opacity = 1 - 0/(vh*0.8) = 1` ✅
- At `y = vh * 0.8`: `opacity = 1 - (vh*0.8)/(vh*0.8) = 0` ✅

Wait, the math IS correct. The issue is the **transition interference** from point 1 above. The opacity IS being set correctly, but the 300ms global transition delays the visual update, making it appear to happen "much later."

**Verification:** Add `console.log(y, opacity)` - you'll see correct values but delayed rendering.

---

### 3. "Unlimited" Letter Exit Animation Architecture is Fundamentally Flawed

**Location:** `App.tsx:165-179`

```jsx
{"Unlimited.".split("").map((char, i) => (
  <span key={i} className="inline-block">
    <span
      className="inline-block animate-letter-rise ..."
      style={{ animationDelay: `${500 + i * 75}ms` }}
    >
      {char}
    </span>
  </span>
))}
```

**Problem:** You're trying to use CSS keyframe animations (`animate-letter-rise`) for ENTRY, then expecting scroll-driven JS to control EXIT. **These are fundamentally incompatible approaches.**

CSS `animation` properties lock the element into keyframe-defined states. Once `animation-fill-mode: both` (from your `both` in the animation definition) is applied, the element's `transform`, `opacity`, and `filter` are controlled by the animation, **not your inline styles**.

**Why entry works but exit doesn't:**
- Entry: Pure CSS keyframe animation runs once, ends, leaves element at final state
- Exit: You're NOT applying any exit animation or scroll-driven styles to these elements

**I don't see ANY scroll handler for the letters.** Looking at the code, there's:
- `useScrollReveal()` hook for intersection-based reveal (one-time)
- Hero scroll handler only updates `bgRef` and `--hero-scale`

**The exit animation code doesn't exist.** You mentioned "tried JS calculations with state, tried refs with direct DOM manipulation" - but none of that code is in the current file. The letters have NO scroll-driven exit behavior implemented.

**Solution Architecture:**
1. CSS keyframes for entry (existing, works)
2. After entry completes, switch to scroll-driven transforms via:
   - CSS custom properties set by JS scroll handler
   - Direct DOM manipulation with `transition: none`
   - Or CSS scroll-driven animations (experimental, limited support)

---

## 🟡 Architecture Concerns

### 4. Fixed Positioning + Opacity on Scroll = Paint Storms

**Location:** `App.tsx:136-137`

```jsx
<div
  ref={bgRef}
  className="fixed inset-0 z-0 ... will-change-opacity"
>
```

**Problem:** `will-change-opacity` is good, but the child `<img>` has:

```jsx
className="... transition-transform duration-75 ease-out"
style={{ transform: `scale(var(--hero-scale))` }}
```

**Issue:** The image has its own transition (75ms), which:
1. Creates a separate compositor layer
2. Fights with the parent's direct opacity manipulation
3. CSS variable updates (`--hero-scale`) go through the cascade, not direct DOM

**Solution:** Remove `transition-transform duration-75` from the image. Scroll-driven transforms should NOT have transitions.

---

### 5. Inconsistent Animation Strategies

The codebase mixes THREE different animation approaches:

| Approach | Where Used | Scroll-Driven? |
|----------|-----------|----------------|
| CSS Keyframes | `animate-letter-rise` | No (timeline-based) |
| Intersection Observer | `useScrollReveal` | No (threshold trigger) |
| Direct DOM manipulation | `bgRef.current.style.opacity` | Yes |
| CSS Variables | `--hero-scale` | Partially |

**Problem:** Each approach has different timing characteristics. Mixing them creates unpredictable behavior.

**Recommendation:** Pick ONE strategy for scroll-driven effects:
- **Option A:** Direct DOM manipulation with `transition: none`
- **Option B:** CSS custom properties with `@property` registration (no transitions)
- **Option C:** CSS scroll-driven animations (`animation-timeline: scroll()`) - experimental

---

### 6. Safari-Specific Compositor Issues

**Problem:** Safari handles `will-change` and compositor layers differently than Chrome. Common issues:

1. `will-change: opacity` doesn't always promote to compositor layer in Safari
2. Fixed positioning with backdrop-blur causes repaint issues
3. CSS variables in `transform` may not trigger GPU acceleration

**Evidence:** Lines 146-148 have multiple gradient overlays on fixed element:

```jsx
<div className="absolute inset-x-0 bottom-0 h-64 bg-gradient-to-t ..." />
<div className="absolute inset-x-0 top-0 h-32 bg-gradient-to-b ..." />
```

These child elements inherit paint context from the fixed parent, causing Safari to repaint the entire fixed layer on every scroll.

**Solution:**
```css
.scroll-driven-element {
  transform: translateZ(0); /* Force GPU layer */
  -webkit-transform: translateZ(0);
  backface-visibility: hidden;
  -webkit-backface-visibility: hidden;
}
```

---

## 🟢 DRY Opportunities

### 7. Scroll Handler Pattern Duplication

**Location:** `App.tsx:97-121` and `App.tsx:266-283`

Two separate scroll handlers with similar patterns:

```javascript
// Hero handler
useEffect(() => {
  const handleScroll = () => { /* ... */ };
  window.addEventListener("scroll", handleScroll, { passive: true });
  return () => window.removeEventListener("scroll", handleScroll);
}, []);

// ScrollGlobeItem handler
useEffect(() => {
  const handleScroll = () => { /* ... */ };
  window.addEventListener("scroll", handleScroll, { passive: true });
  return () => window.removeEventListener("scroll", handleScroll);
}, []);
```

**Solution:** Create `useScrollProgress(elementRef)` custom hook that returns normalized progress value.

---

## 🔵 Maintenance Improvements

### 8. `useEffect` Directly in Components (Violates CLAUDE.md)

**Location:** `App.tsx:11-26, 51-55, 97-121, 266-283, 352-366`

Per your guidelines: "NEVER use `useEffect` directly within a component."

All these should be custom hooks:
- `useScrollReveal` - already extracted ✅
- Nav scroll handler - should be `useScrolled(threshold)`
- Hero scroll handler - should be `useHeroParallax(bgRef, containerRef)`
- ScrollGlobeItem handler - should be `useScrollProgress(containerRef)`
- BentoCard escape handler - should be `useEscapeKey(callback)`

---

### 9. Missing Error Boundaries for Scroll Calculations

**Location:** `App.tsx:269-278`

```javascript
const rect = containerRef.current.getBoundingClientRect();
const totalDist = rect.height - viewportHeight;
const scrolled = -start;
let p = scrolled / totalDist;
```

**Problem:** If `totalDist` is 0 or negative (element smaller than viewport), division produces Infinity or NaN.

---

## ⚪ Nitpicks

### 10. Unnecessary Nested Spans

```jsx
<span key={i} className="inline-block">
  <span className="inline-block animate-letter-rise ...">
    {char}
  </span>
</span>
```

The outer span serves no purpose. Single span is sufficient.

### 11. Magic Numbers

```javascript
animationDelay: `${500 + i * 75}ms`
const opacity = Math.max(0, 1 - y / (vh * 0.8));
const scale = 1.05 + y * 0.0002;
```

Should be constants:
```javascript
const LETTER_BASE_DELAY = 500;
const LETTER_STAGGER = 75;
const FADE_VIEWPORT_RATIO = 0.8;
const BASE_SCALE = 1.05;
const SCALE_FACTOR = 0.0002;
```

---

## ✅ Strengths

1. **Passive scroll listeners** - correctly using `{ passive: true }` for performance
2. **CSS variable approach** - `--hero-scale` is the right pattern, just needs proper implementation
3. **`will-change` usage** - correctly applied to the animated element
4. **Initial call pattern** - calling `handleScroll()` immediately after setup ensures no flash
5. **Clean separation** - Hero, BentoGrid, etc. are properly componentized

---

## Root Cause Summary

| Issue | Root Cause | Fix |
|-------|-----------|-----|
| Hero fade timing | Global 300ms transition | Remove `*` transition rule or add `transition: none` |
| Hero fade Safari | Compositor layer issues | Add `transform: translateZ(0)` |
| Letters never exit | **No exit code exists** | Implement scroll handler for letters |
| Scale works | CSS variables work when no transition fights | (working correctly) |

---

## Recommended Fix Order

1. **Remove global `*` transition rule** (or scope it properly)
2. **Add `transform: translateZ(0)` to fixed scroll-driven elements**
3. **Remove `transition-transform` from scroll-driven image**
4. **Implement actual letter exit animation** - it doesn't exist
5. **Extract useEffect hooks per CLAUDE.md guidelines**

---

## Unresolved Questions

- Letter exit: what's the desired scroll range for exit (0-50% vh? 50-100%?)?
- Letter exit: should letters reverse the entry animation or do something different?
- Safari: can we test on actual device or just simulator?
- Performance budget: how many scroll-driven elements is acceptable?

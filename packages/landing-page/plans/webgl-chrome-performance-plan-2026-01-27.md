# WebGL Chrome Performance Update Plan (2026-01-27)

## Goal
Stabilize Chrome performance (no slideshow) while preserving Safari’s high-quality visuals and keeping the mesh behavior consistent across browsers.

## Current Diagnosis (Summary)
- Chrome looks different by design (lower quality tier: no transmission, reduced bloom).
- Chrome slows down because engine-level caps are not enforced; node count can grow to 80+, creating hundreds of connection meshes and heavy postprocessing overhead.
- Per-connection timers and per-frame material mutations amplify CPU/GPU load in Chrome.

## Update Plan
1) **Measure + confirm baseline**
   - Add lightweight counters or dev-only stats for: node count, connection count, draw calls, FPS.
   - Capture baseline behavior in Chrome and Safari.

2) **Enforce browser-tier limits at engine level**
   - Pipe quality tier into engine config (`maxNodes`, appearance/disappearance rates, optional maxConnections).
   - Ensure Chrome cannot exceed its tier regardless of initial props.

3) **Reduce per-connection overhead in lower tiers**
   - Replace per-connection `setInterval`/`setTimeout` with a shared scheduler.
   - Disable non-critical meshes in medium/low tiers (pulse spheres, flash spheres).

4) **Lower render cost in Chrome**
   - Reduce DPR upper bound for Chrome.
   - Reduce or disable postprocessing for medium/low tiers.
   - Throttle expensive material state changes further; keep only essential uniform updates per frame.

5) **Validate & compare**
   - Verify Safari remains high quality.
   - Verify Chrome is smooth with acceptable visual downgrade.
   - Capture before/after metrics and screenshots.

## Done Criteria
- Chrome maintains smooth FPS with no slideshow on typical hardware.
- Safari visuals remain unchanged.
- Node and connection counts are bounded per quality tier.
- Postprocessing cost is appropriately scaled in Chrome.

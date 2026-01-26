import createGlobe from "cobe";
import { useEffect, useRef } from "react";
import { useNetwork } from "../context/NetworkContext";

export function NetworkGlobe() {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const pointerInteracting = useRef(null);
  const pointerInteractionMovement = useRef(0);
  const { nodesOnline } = useNetwork();

  // Use a ref to hold markers so onRender can access fresh data without re-running useEffect
  const markersRef = useRef<{ location: [number, number]; size: number; flash?: boolean }[]>([
    { location: [37.7595, -122.4367], size: 0.03 }, // SF
    { location: [40.7128, -74.0060], size: 0.03 }, // NY
    { location: [51.5074, -0.1278], size: 0.03 }, // London
    { location: [35.6762, 139.6503], size: 0.03 }, // Tokyo
    { location: [-33.8688, 151.2093], size: 0.03 }, // Sydney
    { location: [52.5200, 13.4050], size: 0.03 }, // Berlin
    { location: [1.3521, 103.8198], size: 0.03 }, // Singapore
    { location: [12.9716, 77.5946], size: 0.03 }, // Bangalore
    { location: [-23.5505, -46.6333], size: 0.03 }, // São Paulo
  ]);

  // Sync markers count with nodesOnline
  useEffect(() => {
    const currentCount = markersRef.current.length;

    if (nodesOnline > currentCount) {
      // Add new nodes
      const needed = nodesOnline - currentCount;
      for (let i = 0; i < needed; i++) {
        markersRef.current.push({
          location: [
            (Math.random() - 0.5) * 160,
            (Math.random() - 0.5) * 360
          ],
          size: 0 // Start at size 0 for animation
        });
      }
    } else if (nodesOnline < currentCount) {
      // Remove simulated nodes (keep the first 9 fixed hubs if possible)
      const removeCount = currentCount - nodesOnline;
      // Ideally we only remove from index 9 onwards
      if (markersRef.current.length > 9) {
        const removable = markersRef.current.length - 9;
        const toRemove = Math.min(removeCount, removable);
        // Remove from end
        markersRef.current.splice(markersRef.current.length - toRemove, toRemove);
      }
    }
  }, [nodesOnline]);

  useEffect(() => {
    let phi = 0;

    if (!canvasRef.current) return;

    const globe = createGlobe(canvasRef.current, {
      devicePixelRatio: 2,
      width: 600 * 2,
      height: 600 * 2,
      phi: 0,
      theta: 0,
      dark: 1,
      diffuse: 1.2,
      mapSamples: 16000,
      mapBrightness: 6,
      baseColor: [0.3, 0.3, 0.3],
      markerColor: [0.1, 0.8, 1],
      glowColor: [0.4, 0.4, 0.5],
      markers: [], // We update this in onRender
      onRender: (state) => {
        // Called on every animation frame.
        if (!pointerInteracting.current) {
          phi += 0.003;
        }
        state.phi = phi + pointerInteractionMovement.current;

        // Animate marker sizes (Twinkling effect)
        // We use phi as a time source for the sin wave
        markersRef.current.forEach(m => {
          // If this is a new marker (size near 0), grow it in
          // Otherwise, pulse it
          if (m.size < 0.03 && !m.flash) {
            m.size += 0.002;
          } else {
            // Mark as active/flashing
            m.flash = true;
            // Pulse between 0.015 and 0.045
            // Use marker's unique location as a seed for phase to avoid uniform pulsing
            const phase = m.location[0] + m.location[1];
            // Speed varies slightly by location too
            const speed = 3 + Math.abs(m.location[0] / 50);

            const sine = Math.sin((phi * speed) + phase);
            // map -1..1 to 0.02..0.04
            m.size = 0.03 + (sine * 0.015);
          }
        });

        state.markers = markersRef.current;
      },
    });

    return () => {
      globe.destroy();
    };
  }, []);

  return (
    <div
      className="absolute inset-0 z-0 flex items-center justify-center opacity-70 mix-blend-plus-lighter cursor-grab active:cursor-grabbing"
      onPointerDown={(e) => {
        // @ts-ignore
        pointerInteracting.current = e.clientX - pointerInteractionMovement.current;
      }}
      onPointerUp={() => {
        // @ts-ignore
        pointerInteracting.current = null;
      }}
      onPointerOut={() => {
        // @ts-ignore
        pointerInteracting.current = null;
      }}
      onMouseMove={(e) => {
        if (pointerInteracting.current !== null) {
          const delta = e.clientX - (pointerInteracting.current as unknown as number);
          pointerInteractionMovement.current = delta * 0.005;
        }
      }}
      onTouchMove={(e) => {
        if (pointerInteracting.current !== null && e.touches[0]) {
          const delta = e.touches[0].clientX - (pointerInteracting.current as unknown as number);
          pointerInteractionMovement.current = delta * 0.005;
        }
      }}
    >
      <canvas
        ref={canvasRef}
        style={{ width: 600, height: 600, maxWidth: "100%", aspectRatio: 1 }}
      />
    </div>
  );
}

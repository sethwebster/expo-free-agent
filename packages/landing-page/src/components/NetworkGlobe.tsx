import createGlobe from "cobe";
import { useEffect, useRef } from "react";
import { useNetwork } from "../context/NetworkContext";

export function NetworkGlobe() {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const { nodesOnline } = useNetwork();

  // Use a ref to hold markers so onRender can access fresh data without re-running useEffect
  const markersRef = useRef([
    { location: [37.7595, -122.4367] as [number, number], size: 0.03 }, // SF
    { location: [40.7128, -74.0060] as [number, number], size: 0.03 }, // NY
    { location: [51.5074, -0.1278] as [number, number], size: 0.03 }, // London
    { location: [35.6762, 139.6503] as [number, number], size: 0.03 }, // Tokyo
    { location: [-33.8688, 151.2093] as [number, number], size: 0.03 }, // Sydney
    { location: [52.5200, 13.4050] as [number, number], size: 0.03 }, // Berlin
    { location: [1.3521, 103.8198] as [number, number], size: 0.03 }, // Singapore
    { location: [12.9716, 77.5946] as [number, number], size: 0.03 }, // Bangalore
    { location: [-23.5505, -46.6333] as [number, number], size: 0.03 }, // São Paulo
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
        state.phi = phi;
        phi += 0.003;

        // Animate marker sizes and update state
        markersRef.current.forEach(m => {
          // Easing in
          if (m.size < 0.03) {
            m.size += 0.0005;
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
    <div className="absolute inset-0 z-0 flex items-center justify-center opacity-70 mix-blend-plus-lighter pointer-events-none">
      <canvas
        ref={canvasRef}
        style={{ width: 600, height: 600, maxWidth: "100%", aspectRatio: 1 }}
      />
    </div>
  );
}

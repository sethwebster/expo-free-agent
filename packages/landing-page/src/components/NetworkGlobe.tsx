import createGlobe from "cobe";
import { useEffect, useRef } from "react";

export function NetworkGlobe() {
  const canvasRef = useRef<HTMLCanvasElement>(null);

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
      glowColor: [0.4, 0.4, 0.5], // Zinc-like glow
      markers: [
        // Random locations representing distributed workers
        { location: [37.7595, -122.4367], size: 0.03 }, // SF
        { location: [40.7128, -74.0060], size: 0.03 }, // NY
        { location: [51.5074, -0.1278], size: 0.03 }, // London
        { location: [35.6762, 139.6503], size: 0.03 }, // Tokyo
        { location: [-33.8688, 151.2093], size: 0.03 }, // Sydney
        { location: [52.5200, 13.4050], size: 0.03 }, // Berlin
        { location: [1.3521, 103.8198], size: 0.03 }, // Singapore
        { location: [12.9716, 77.5946], size: 0.03 }, // Bangalore
        { location: [-23.5505, -46.6333], size: 0.03 }, // São Paulo
      ],
      onRender: (state) => {
        // Called on every animation frame.
        // `state` will be an empty object, return updated params.
        state.phi = phi;
        phi += 0.003;
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

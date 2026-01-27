import createGlobe from "cobe";
import { useEffect, useRef, useMemo } from "react";
import { useNetworkContext } from "../contexts/NetworkContext";

interface NetworkGlobeProps {
  scrollProgress?: number;
}

export function NetworkGlobe({ scrollProgress = 1 }: NetworkGlobeProps) {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const pointerInteracting = useRef(null);
  const pointerInteractionMovement = useRef(0);
  const { stats } = useNetworkContext();
  const nodesOnline = stats.nodesOnline;
  const phiRef = useRef(0);

  // Keep markers at a constant size matching the land dots
  // The CSS scale will make them appear appropriately sized
  const markerSize = 0.03; // Match land dot size

  // Generate many markers distributed around the globe (computed once)
  const initialMarkers = useMemo(() => {
    const markers: { location: [number, number]; size: number; flash?: boolean }[] = [];

    // Major cities (brighter/larger)
    const cities = [
      [37.7595, -122.4367], // SF
      [40.7128, -74.0060], // NY
      [51.5074, -0.1278], // London
      [35.6762, 139.6503], // Tokyo
      [-33.8688, 151.2093], // Sydney
      [52.5200, 13.4050], // Berlin
      [1.3521, 103.8198], // Singapore
      [12.9716, 77.5946], // Bangalore
      [-23.5505, -46.6333], // São Paulo
      [55.7558, 37.6173], // Moscow
      [39.9042, 116.4074], // Beijing
      [19.4326, -99.1332], // Mexico City
      [-22.9068, -43.1729], // Rio
      [48.8566, 2.3522], // Paris
      [41.9028, 12.4964], // Rome
    ];

    cities.forEach(([lat, lng]) => {
      markers.push({ location: [lat, lng], size: markerSize * 1.5, flash: false });
    });

    // Add 15000 random distributed nodes for dense coverage
    for (let i = 0; i < 15000; i++) {
      markers.push({
        location: [
          (Math.random() - 0.5) * 160, // lat: -80 to 80
          (Math.random() - 0.5) * 360  // lng: -180 to 180
        ],
        size: markerSize,
        flash: false
      });
    }

    return markers;
  }, [markerSize]);

  const markersRef = useRef(initialMarkers);

  // Keep the static 15k markers - don't sync with nodesOnline
  // This ensures a visually dense globe regardless of live stats

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
          phi += 0.00375;
        }
        phiRef.current = phi; // Update for arc rendering
        state.phi = phi + pointerInteractionMovement.current;

        // Animate marker sizes (Pulsing effect)
        // We use phi as a time source for the sin wave
        markersRef.current.forEach((m, i) => {
          // Use marker's unique location as a seed for phase to avoid uniform pulsing
          const phase = m.location[0] + m.location[1];
          // Speed varies by marker to create organic pulsing
          const speed = 2 + (i % 5) * 0.5;

          const sine = Math.sin((phi * speed) + phase);
          // Pulse between 50% and 150% of base size
          const baseSize = i < 15 ? markerSize * 1.5 : markerSize; // Cities are larger
          m.size = baseSize * (0.7 + (sine * 0.4));
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

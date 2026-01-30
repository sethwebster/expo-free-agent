import { useEffect, RefObject, MutableRefObject } from "react";
import createGlobe from "cobe";

interface UseCobeGlobeParams {
  canvasRef: RefObject<HTMLCanvasElement>;
  pointerInteracting: MutableRefObject<number | null>;
  pointerInteractionMovement: MutableRefObject<number>;
  phiRef: MutableRefObject<number>;
  markersRef: MutableRefObject<{ location: [number, number]; size: number; flash?: boolean }[]>;
  markerSize: number;
}

export function useCobeGlobe({
  canvasRef,
  pointerInteracting,
  pointerInteractionMovement,
  phiRef,
  markersRef,
  markerSize,
}: UseCobeGlobeParams) {
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
      markers: [],
      onRender: (state) => {
        if (!pointerInteracting.current) {
          phi += 0.00375;
        }
        phiRef.current = phi;
        state.phi = phi + pointerInteractionMovement.current;

        markersRef.current.forEach((m, i) => {
          const phase = m.location[0] + m.location[1];
          const speed = 2 + (i % 5) * 0.5;

          const sine = Math.sin((phi * speed) + phase);
          const baseSize = i < 15 ? markerSize * 1.5 : markerSize;
          m.size = baseSize * (0.7 + (sine * 0.4));
        });

        state.markers = markersRef.current;
      },
    });

    return () => {
      globe.destroy();
    };
  }, [canvasRef, pointerInteracting, pointerInteractionMovement, phiRef, markersRef, markerSize]);
}

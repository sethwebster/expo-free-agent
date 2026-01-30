import { useEffect, useState } from 'react';

interface ScrollProgressState {
  scrollProgress: number;
  blurAmount: number;
  titleScrollProgress: number;
}

export function useScrollProgress() {
  const [state, setState] = useState<ScrollProgressState>({
    scrollProgress: 0,
    blurAmount: 0,
    titleScrollProgress: 0,
  });

  useEffect(() => {
    const handleScroll = () => {
      const scrollY = window.scrollY;
      const viewportHeight = window.innerHeight;

      // Phase 1: Scroll hero content with blur (0 to 0.8vh)
      const heroScrollProgress = Math.min(scrollY / (viewportHeight * 0.8), 1);
      const blurAmount = heroScrollProgress * 20; // 0 to 20px blur
      const titleScrollProgress = heroScrollProgress; // 0 to 1 for character exit

      // Phase 2: After hero scrolled away, move camera for globe reveal (after 0.8vh, over 2vh)
      const cameraProgress = Math.max(0, Math.min(1, (scrollY - viewportHeight * 0.8) / (viewportHeight * 2)));

      setState({
        scrollProgress: cameraProgress,
        blurAmount,
        titleScrollProgress,
      });
    };

    window.addEventListener("scroll", handleScroll);
    return () => window.removeEventListener("scroll", handleScroll);
  }, []);

  return state;
}

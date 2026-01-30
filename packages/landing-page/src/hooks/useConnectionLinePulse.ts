import { useEffect, MutableRefObject } from 'react';

interface PulseState {
  progress: number | null;
  direction: 'forward' | 'backward';
  active: boolean;
  departureNodeId: number | null;
}

export function useConnectionLinePulse(
  index: number,
  fromId: number,
  toId: number,
  pulseFrequencyScale: number,
  isActiveRef: MutableRefObject<boolean>,
  pulseState: MutableRefObject<PulseState>,
  onPulseDepartureRef: MutableRefObject<(nodeId: number) => void>
) {
  useEffect(() => {
    const triggerPulse = () => {
      if (!isActiveRef.current) {
        return;
      }

      if (!pulseState.current.active && Math.random() < 0.4) {
        pulseState.current.progress = 0;
        pulseState.current.direction = Math.random() < 0.5 ? 'forward' : 'backward';
        pulseState.current.active = true;

        const departingNodeId =
          pulseState.current.direction === 'forward' ? fromId : toId;
        pulseState.current.departureNodeId = departingNodeId;

        onPulseDepartureRef.current(departingNodeId);
      }
    };

    const baseInterval = 4000 / Math.max(0.2, pulseFrequencyScale);
    const randomVariance = 2000 / Math.max(0.2, pulseFrequencyScale);

    const initialDelay = 500 + index * 150 + Math.random() * 1000;
    const timeout = setTimeout(triggerPulse, initialDelay);

    const interval = setInterval(
      triggerPulse,
      baseInterval + Math.random() * randomVariance
    );

    return () => {
      clearTimeout(timeout);
      clearInterval(interval);
    };
  }, [index, fromId, toId, pulseFrequencyScale, isActiveRef, pulseState, onPulseDepartureRef]);
}

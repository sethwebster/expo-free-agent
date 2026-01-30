import { useEffect, useMemo } from 'react';
import { getGeometry, acquirePool, releasePool } from '../components/HeroVisualization/geometryPool';
import {
  createEmissiveMaterial,
  disposeMaterial,
} from '../components/HeroVisualization/materialPool';
import { COLORS } from '../components/HeroVisualization/constants';

export function useConnectionLineGeometry() {
  useEffect(() => {
    acquirePool();
    return () => releasePool();
  }, []);

  const unitCylinderGeometry = useMemo(() => getGeometry('cylinderUnit'), []);
  const pulseGeometry = useMemo(() => getGeometry('sphereSmall'), []);
  const flashGeometry = useMemo(() => getGeometry('sphereMedium'), []);

  const innerTubeMaterial = useMemo(
    () => createEmissiveMaterial(COLORS.WHITE, false),
    []
  );
  const outerTubeMaterial = useMemo(
    () => createEmissiveMaterial(COLORS.INDIGO, false),
    []
  );
  const pulseMaterial = useMemo(
    () => createEmissiveMaterial(COLORS.WHITE),
    []
  );
  const flashMaterialFrom = useMemo(
    () => createEmissiveMaterial(COLORS.WHITE),
    []
  );
  const flashMaterialTo = useMemo(
    () => createEmissiveMaterial(COLORS.WHITE),
    []
  );

  useEffect(() => {
    return () => {
      disposeMaterial(innerTubeMaterial);
      disposeMaterial(outerTubeMaterial);
      disposeMaterial(pulseMaterial);
      disposeMaterial(flashMaterialFrom);
      disposeMaterial(flashMaterialTo);
    };
  }, [
    innerTubeMaterial,
    outerTubeMaterial,
    pulseMaterial,
    flashMaterialFrom,
    flashMaterialTo,
  ]);

  return {
    unitCylinderGeometry,
    pulseGeometry,
    flashGeometry,
    innerTubeMaterial,
    outerTubeMaterial,
    pulseMaterial,
    flashMaterialFrom,
    flashMaterialTo,
  };
}

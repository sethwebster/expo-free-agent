import { useEffect, useMemo } from 'react';
import * as THREE from 'three';
import { getGeometry, createEdgesGeometry, acquirePool, releasePool } from '../components/HeroVisualization/geometryPool';
import {
  cloneGlassMaterial,
  createEmissiveMaterial,
  createLineMaterial,
  createPointMaterial,
  disposeMaterial,
} from '../components/HeroVisualization/materialPool';
import { COLORS } from '../components/HeroVisualization/constants';
import { getQualitySettings } from '../components/HeroVisualization/quality';

export function useMeshNodeGeometry() {
  useEffect(() => {
    acquirePool();
    return () => releasePool();
  }, []);

  const geometry = useMemo(() => getGeometry('icosahedron'), []);
  const innerCoreGeometry = useMemo(() => getGeometry('innerCore'), []);
  const bigBangGeometry = useMemo(() => getGeometry('sphereLarge'), []);
  const edgesGeometry = useMemo(() => createEdgesGeometry(geometry), [geometry]);

  const material = useMemo(() => cloneGlassMaterial(), []);
  const edgeMaterial = useMemo(() => createLineMaterial(), []);
  const innerCoreMaterial = useMemo(() => createEmissiveMaterial(COLORS.GLOW_GREEN, false), []);
  const bigBangMaterial = useMemo(() => createEmissiveMaterial(COLORS.WHITE), []);
  const particleRingMaterial = useMemo(() => createPointMaterial(COLORS.WHITE, 0.15), []);

  const qualitySettings = useMemo(() => getQualitySettings(), []);
  const particleCount = qualitySettings.particleCount;

  const particleRingGeometry = useMemo(() => {
    const geom = new THREE.BufferGeometry();
    const positions = new Float32Array(particleCount * 3);
    const velocities = new Float32Array(particleCount * 3);

    for (let i = 0; i < particleCount; i++) {
      const angle = (i / particleCount) * Math.PI * 2;
      const radius = 1;
      positions[i * 3] = Math.cos(angle) * radius;
      positions[i * 3 + 1] = Math.sin(angle) * radius;
      positions[i * 3 + 2] = 0;

      const speed = 0.5 + Math.random() * 1.5;
      const angleVariance = (Math.random() - 0.5) * 0.8;
      velocities[i * 3] = Math.cos(angle + angleVariance) * speed;
      velocities[i * 3 + 1] = Math.sin(angle + angleVariance) * speed;
      velocities[i * 3 + 2] = (Math.random() - 0.5) * 0.5;
    }

    geom.setAttribute('position', new THREE.BufferAttribute(positions, 3));
    return { geometry: geom, velocities };
  }, [particleCount]);

  useEffect(() => {
    return () => {
      edgesGeometry.dispose();
      particleRingGeometry.geometry.dispose();
      disposeMaterial(material);
      disposeMaterial(edgeMaterial);
      disposeMaterial(innerCoreMaterial);
      disposeMaterial(bigBangMaterial);
      disposeMaterial(particleRingMaterial);
    };
  }, [
    edgesGeometry,
    particleRingGeometry,
    material,
    edgeMaterial,
    innerCoreMaterial,
    bigBangMaterial,
    particleRingMaterial,
  ]);

  return {
    geometry,
    innerCoreGeometry,
    bigBangGeometry,
    edgesGeometry,
    material,
    edgeMaterial,
    innerCoreMaterial,
    bigBangMaterial,
    particleRingMaterial,
    particleRingGeometry: particleRingGeometry.geometry,
    particleVelocities: particleRingGeometry.velocities,
    particleCount,
  };
}

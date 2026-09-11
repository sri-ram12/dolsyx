'use client';

import React, { useEffect, useRef } from 'react';
import { ParticleConfig } from './emoji-profiles';

interface EmojiParticleCanvasProps {
  config: ParticleConfig;
  intensity?: number;
  onComplete: () => void;
}

interface Particle {
  x: number;
  y: number;
  vx: number;
  vy: number;
  rotation: number;
  vRot: number;
  size: number;
  color: string;
  age: number;
  lifespan: number;
  opacity: number;
}

export const EmojiParticleCanvas: React.FC<EmojiParticleCanvasProps> = ({
  config,
  intensity = 1.0,
  onComplete,
}) => {
  const canvasRef = useRef<HTMLCanvasElement>(null);

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;
    const ctx = canvas.getContext('2d');
    if (!ctx) return;

    // Fixed canvas coordinates for sharp rendering on retina displays
    const dpr = typeof window !== 'undefined' ? window.devicePixelRatio || 1 : 1;
    const size = 160;
    canvas.width = size * dpr;
    canvas.height = size * dpr;
    ctx.scale(dpr, dpr);

    const centerX = size / 2;
    const centerY = size / 2;

    // Calculate dynamic particle count bounded to safe limits
    const baseCount = config.count || 10;
    const scaledCount = Math.min(Math.round(baseCount * intensity), 28);

    const colors = config.colors || ['#EF4444', '#F59E0B', '#3B82F6'];
    const particles: Particle[] = [];

    for (let i = 0; i < scaledCount; i++) {
      let angle: number;
      if (config.type === 'hearts' || config.type === 'flames') {
        // Upward cone
        const spreadRad = (config.spread * Math.PI) / 180;
        angle = -Math.PI / 2 + (Math.random() - 0.5) * spreadRad;
      } else if (config.type === 'tears') {
        // Downward stream
        const spreadRad = (config.spread * Math.PI) / 180;
        angle = Math.PI / 2 + (Math.random() - 0.5) * spreadRad;
      } else {
        // Radial 360 spread
        angle = Math.random() * Math.PI * 2;
      }

      const speed = (config.speed * (0.6 + Math.random() * 0.8) * intensity) / 18;
      const lifespan = 30 + Math.random() * 25; // 30-55 frames (~500ms - 900ms)

      particles.push({
        x: centerX + (Math.random() - 0.5) * 14,
        y: centerY + (Math.random() - 0.5) * 14,
        vx: Math.cos(angle) * speed,
        vy: Math.sin(angle) * speed,
        rotation: Math.random() * Math.PI * 2,
        vRot: (Math.random() - 0.5) * 0.25,
        size: (4.5 + Math.random() * 4) * (config.maxScale || 1.0),
        color: colors[i % colors.length],
        age: 0,
        lifespan,
        opacity: 1.0,
      });
    }

    let animationFrameId: number;

    const render = () => {
      ctx.clearRect(0, 0, size, size);

      let activeParticles = 0;

      for (let i = 0; i < particles.length; i++) {
        const p = particles[i];
        p.age++;

        if (p.age >= p.lifespan) continue;
        activeParticles++;

        // Physics updates
        p.vy += config.gravity || 0.08;
        p.x += p.vx;
        p.y += p.vy;
        p.rotation += p.vRot;

        // Fade out in the last 40% of life
        const lifeRatio = p.age / p.lifespan;
        p.opacity = lifeRatio > 0.6 ? 1 - (lifeRatio - 0.6) / 0.4 : 1.0;

        ctx.save();
        ctx.translate(p.x, p.y);
        ctx.rotate(p.rotation);
        ctx.globalAlpha = Math.max(0, p.opacity);
        ctx.fillStyle = p.color;

        // Render type-specific vector particle
        switch (config.type) {
          case 'hearts': {
            // Draw smooth heart shape
            const s = p.size * 0.6;
            ctx.beginPath();
            ctx.moveTo(0, s * 0.3);
            ctx.bezierCurveTo(-s, -s * 0.5, -s * 1.5, s * 0.5, 0, s * 1.6);
            ctx.bezierCurveTo(s * 1.5, s * 0.5, s, -s * 0.5, 0, s * 0.3);
            ctx.fill();
            break;
          }

          case 'tears': {
            // Draw teardrop droplet
            const s = p.size * 0.7;
            ctx.beginPath();
            ctx.arc(0, 0, s, 0, Math.PI);
            ctx.lineTo(0, -s * 1.6);
            ctx.closePath();
            ctx.fill();
            break;
          }

          case 'confetti': {
            // Fluttering rectangular ribbon
            const w = p.size * 1.4;
            const h = p.size * 0.65;
            ctx.fillRect(-w / 2, -h / 2, w, h);
            break;
          }

          case 'flames': {
            // Rising glowing ember
            const s = p.size * 0.8;
            ctx.beginPath();
            ctx.arc(0, 0, s, 0, Math.PI * 2);
            ctx.fill();
            break;
          }

          case 'stars':
          case 'sparks': {
            // 4-point glint star
            const s = p.size;
            ctx.beginPath();
            ctx.moveTo(0, -s);
            ctx.quadraticCurveTo(0, 0, s, 0);
            ctx.quadraticCurveTo(0, 0, 0, s);
            ctx.quadraticCurveTo(0, 0, -s, 0);
            ctx.quadraticCurveTo(0, 0, 0, -s);
            ctx.fill();
            break;
          }

          default: {
            // Soft circle particle
            ctx.beginPath();
            ctx.arc(0, 0, p.size * 0.5, 0, Math.PI * 2);
            ctx.fill();
            break;
          }
        }

        ctx.restore();
      }

      if (activeParticles > 0) {
        animationFrameId = requestAnimationFrame(render);
      } else {
        onComplete();
      }
    };

    animationFrameId = requestAnimationFrame(render);

    return () => {
      cancelAnimationFrame(animationFrameId);
    };
  }, [config, intensity, onComplete]);

  return (
    <canvas
      ref={canvasRef}
      className="pointer-events-none absolute left-1/2 top-1/2 -translate-x-1/2 -translate-y-1/2 z-30"
      style={{
        width: 160,
        height: 160,
      }}
    />
  );
};

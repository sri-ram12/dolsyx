import fs from 'fs';
import path from 'path';

export interface ImagePreset {
  id: string;
  name: string;
  suffix: string;
}

export class ImagePipelineEngine {
  public static readonly PRESETS: Record<string, string> = {
    photorealistic: 'highly detailed 8k photorealistic photography, sharp focus, professional lighting, realistic textures',
    cinematic: 'cinematic still, dramatic composition, anamorphic lighting, 35mm film color grading, depth of field',
    anime: 'vibrant anime art style, detailed line art, studio ghibli inspired composition, rich colors',
    '3d': '3d render, octane render, smooth lighting, ray tracing, studio lighting',
    watercolor: 'artistic watercolor painting, delicate brushstrokes, soft pastels, paper texture',
    cyberpunk: 'cyberpunk style, glowing neon lights, futuristic city rain, high contrast, dark atmospheric',
    minimalist: 'clean minimalist graphic design, simple shapes, elegant vector aesthetics, modern typography',
  };

  /**
   * Enhances raw user prompt with visual detail & optional preset styling without altering core intent.
   */
  public static enhancePrompt(rawPrompt: string, preset: string = 'photorealistic', parentPrompt?: string): string {
    let clean = rawPrompt
      .replace(/generate an image of/gi, '')
      .replace(/create an image of/gi, '')
      .replace(/draw a picture of/gi, '')
      .replace(/generate image of/gi, '')
      .replace(/create image of/gi, '')
      .replace(/generate pic/gi, '')
      .replace(/generate/gi, '')
      .replace(/image of/gi, '')
      .replace(/picture of/gi, '')
      .trim();

    if (!clean || clean.length < 2) {
      clean = 'A sleek silver modern sports car driving on a scenic mountain highway';
    }

    // If parent prompt exists (image editing context), merge context
    if (parentPrompt) {
      clean = `${parentPrompt}, updated with: ${clean}`;
    }

    const presetStyle = this.PRESETS[preset.toLowerCase()] || this.PRESETS.photorealistic;
    return `${clean}, ${presetStyle}`;
  }

  /**
   * Generates dynamic image result URL with seed and parameters
   */
  public static generateImage(rawPrompt: string, preset: string = 'photorealistic', parentPrompt?: string): { imageUrl: string; enhancedPrompt: string; text: string } {
    const enhancedPrompt = this.enhancePrompt(rawPrompt, preset, parentPrompt);
    const seed = Date.now() + Math.floor(Math.random() * 10000);
    const imageUrl = `https://image.pollinations.ai/prompt/${encodeURIComponent(enhancedPrompt)}?width=1024&height=1024&nologo=true&seed=${seed}`;

    const emoji = rawPrompt.toLowerCase().includes('car') || rawPrompt.toLowerCase().includes('porsche') ? '🚗' : '✨';
    return {
      imageUrl,
      enhancedPrompt,
      text: `Here you go ${emoji}`,
    };
  }
}

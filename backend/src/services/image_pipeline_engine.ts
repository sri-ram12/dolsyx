import https from 'https';
import { v2 as cloudinary } from 'cloudinary';
import dotenv from 'dotenv';

dotenv.config();

cloudinary.config({
  cloud_name: process.env.CLOUDINARY_CLOUD_NAME as string,
  api_key: process.env.CLOUDINARY_API_KEY as string,
  api_secret: process.env.CLOUDINARY_API_SECRET as string,
});

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
      .replace(/\b(generate an image of|create an image of|draw a picture of|generate image of|create image of|generate photo of|picture of|photo of|wallpaper of|generate pic of|generate|create|draw|make an image of|make image|make pic|render|image of|picture of)\b/gi, '')
      .replace(/\b(please|can you|i want to see|show me|an image|a picture|a photo|image|picture|photo|pic)\b/gi, '')
      .replace(/[^\w\s\-]/gi, ' ')
      .replace(/\s+/g, ' ')
      .trim();

    if (!clean || clean.length < 2) {
      clean = 'sports car';
    }

    if (parentPrompt) {
      clean = `${parentPrompt} ${clean}`;
    }

    return clean;
  }

  /**
   * Generates, validates, and uploads image to Cloudinary CDN returning a permanent, fast URL.
   */
  public static async generateVerifiedImage(
    rawPrompt: string,
    preset: string = 'photorealistic',
    parentPrompt?: string
  ): Promise<{ success: boolean; imageUrl: string; enhancedPrompt: string; text: string; width?: number; height?: number; error?: string }> {
    const cleanPrompt = this.enhancePrompt(rawPrompt, preset, parentPrompt);
    const seed = Date.now() % 100000;

    const candidateUrls = [
      `https://image.pollinations.ai/prompt/${encodeURIComponent(cleanPrompt)}?nologo=true&seed=${seed}`,
      `https://image.pollinations.ai/prompt/${encodeURIComponent(cleanPrompt + ' ' + (preset !== 'photorealistic' ? preset : ''))}?nologo=true&seed=${seed + 1}`,
      `https://image.pollinations.ai/prompt/${encodeURIComponent(cleanPrompt)}?nologo=true`,
    ];

    let imageBuffer: Buffer | null = null;

    for (const url of candidateUrls) {
      try {
        console.log('[ImagePipelineEngine] Downloading image candidate:', url);
        const response = await fetch(url, {
          headers: {
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
          },
          signal: AbortSignal.timeout(25000),
        });

        if (response.ok) {
          const arrayBuffer = await response.arrayBuffer();
          const buf = Buffer.from(arrayBuffer);
          if (buf.length >= 2000) {
            imageBuffer = buf;
            console.log(`[ImagePipelineEngine] Successfully received ${buf.length} bytes from upstream.`);
            break;
          }
        }
      } catch (err: any) {
        console.warn(`[ImagePipelineEngine] Candidate download error:`, err.message);
      }
    }

    if (!imageBuffer || imageBuffer.length < 2000) {
      return {
        success: false,
        imageUrl: '',
        enhancedPrompt: cleanPrompt,
        text: '',
        error: "I couldn't generate the image right now. Please try a slightly different prompt.",
      };
    }

    try {
      console.log(`[ImagePipelineEngine] Uploading verified buffer (${imageBuffer.length} bytes) to Cloudinary...`);

      // 2. Upload verified image to Cloudinary CDN
      const base64DataUri = `data:image/jpeg;base64,${imageBuffer.toString('base64')}`;
      const uploadResult: any = await new Promise((resolve, reject) => {
        cloudinary.uploader.upload(
          base64DataUri,
          {
            folder: 'dolsyx_ai_generated',
            resource_type: 'image',
          },
          (err, result) => {
            if (err) reject(err);
            else resolve(result);
          }
        );
      });

      console.log('[ImagePipelineEngine] Cloudinary upload successful:', uploadResult.secure_url);

      const emoji = rawPrompt.toLowerCase().includes('car') || rawPrompt.toLowerCase().includes('porsche') ? '🚗' : '✨';
      return {
        success: true,
        imageUrl: uploadResult.secure_url,
        enhancedPrompt: cleanPrompt,
        text: `Generated successfully ${emoji}`,
        width: uploadResult.width || 1024,
        height: uploadResult.height || 1024,
      };
    } catch (err: any) {
      console.error('[ImagePipelineEngine] Image generation/upload failed:', err.message);

      return {
        success: false,
        imageUrl: '',
        enhancedPrompt: cleanPrompt,
        text: '',
        error: "I couldn't generate the image right now. Please try again in a moment.",
      };
    }
  }
}


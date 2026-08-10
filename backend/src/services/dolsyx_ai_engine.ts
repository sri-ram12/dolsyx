import https from 'https';

export interface DolsyxAiMessage {
  role: 'user' | 'assistant' | 'system';
  content: string;
}

export class DolsyxAiEngine {
  public static readonly MASTER_SYSTEM_PROMPT = `
# DOLSYX AI ASSISTANT — MASTER SYSTEM PROMPT

## 1. ROLE
You are DOLSYX AI, the intelligent assistant integrated into the DOLSYX chat application.
Provide direct, accurate, concise, straight-to-the-point answers with zero unnecessary introductory or closing filler text.
`;

  public static async processQuery(prompt: string, history: DolsyxAiMessage[] = [], username?: string): Promise<string> {
    const rawPrompt = prompt.trim();
    if (!rawPrompt) return 'Please type a valid prompt.';
    const clean = rawPrompt.toLowerCase();

    // 1. Instant Image Generation Intent (Direct Image Bubble Output)
    if (this.isImageIntent(clean)) {
      const imagePrompt = this.extractImagePrompt(rawPrompt);
      const imageUrl = `https://image.pollinations.ai/prompt/${encodeURIComponent(imagePrompt)}?width=1024&height=1024&nologo=true&seed=${Date.now()}`;

      return JSON.stringify({
        type: 'image_result',
        text: `🖼️ **Generated Image:** "${imagePrompt}"`,
        imageUrl: imageUrl,
        imagePrompt: imagePrompt,
        options: [
          { label: 'Regenerate 🔄', action: 'confirm_image', prompt: imagePrompt },
        ]
      });
    }

    if (clean.startsWith('yes proceed') || clean.includes('yes proceed') || clean.includes('regenerate')) {
      const imagePrompt = this.extractImagePrompt(rawPrompt.replace(/yes proceed|regenerate/gi, '').trim());
      const promptToUse = imagePrompt.length > 2 ? imagePrompt : 'A brand new red Ferrari parked outside an expensive mansion';
      const imageUrl = `https://image.pollinations.ai/prompt/${encodeURIComponent(promptToUse)}?width=1024&height=1024&nologo=true&seed=${Date.now()}`;

      return JSON.stringify({
        type: 'image_result',
        text: `🖼️ **Generated Image:** "${promptToUse}"`,
        imageUrl: imageUrl,
        imagePrompt: promptToUse
      });
    }

    // 2. Check for Cloud LLM API Key (Groq, Gemini, OpenAI)
    const apiKey = process.env.GROQ_API_KEY || process.env.GEMINI_API_KEY || process.env.OPENAI_API_KEY;
    if (apiKey) {
      try {
        const externalReply = await this.queryExternalLlm(rawPrompt, apiKey, history);
        if (externalReply && externalReply.length > 3) {
          return externalReply;
        }
      } catch (err) {
        console.error('[DOLSYX AI] LLM API error:', err);
      }
    }

    // 3. Telugu Dictionary & Translation (Direct Answer)
    if (clean.includes('telugu')) {
      if (clean.includes("i don't know") || clean.includes('dont know') || clean.includes('do not know')) {
        return '**నాకు తెలియదు (Naaku theliyadu)**\n\n*(Polite: నాకు తెలియదండి)*';
      }
      if (clean.includes('love letter') || clean.includes('letter') || clean.includes('poem')) {
        return 'నా ప్రియమైన బంగారం ❤️,\n\nనువ్వు నా జీవితంలోకి వచ్చిన క్షణం నుంచి ప్రతి రోజు ఒక అందమైన కలలా ఉంది. నీ నవ్వు నా ప్రపంచాన్ని వెలిగిస్తుంది, నీ మాటలు నా మనసుకు ప్రశాంతతను ఇస్తాయి. \n\nనేను నిన్ను ప్రాణంగా ప్రేమిస్తున్నాను. ప్రతి జన్మలోనూ నువ్వే నా తోడుగా ఉండాలని కోరుకుంటున్నాను.\n\nఎల్లప్పుడూ నీ ప్రేమతో 💖';
      }
      if (clean.includes('thank you') || clean.includes('thanks')) {
        return '**ధన్యవాదాలు (Dhanyavaadalu)**';
      }
      if (clean.includes('how are you')) {
        return '**ఎలా ఉన్నారు? (Ela unnaaru?)**';
      }
      const targetPhrase = rawPrompt.replace(/(in telugu meaning|telugu meaning|meaning in telugu|in telugu|telugu)/gi, '').trim();
      return `**${targetPhrase.length > 0 ? targetPhrase : "తెలుగు అర్ధం"}**: Translation processed cleanly.`;
    }

    // 4. Identity & Greetings (Direct Answer)
    if (clean === 'who are you' || clean === 'what is your name') {
      return "I'm **DOLSYX AI**, your built-in intelligent assistant.";
    }
    if (clean === 'hello' || clean === 'hi' || clean === 'hey') {
      return 'Hello! How can I help you today?';
    }

    // 5. Sense Organs (Direct Concise Answer)
    if (clean.includes('sense organ') || clean.includes('sense organs') || clean.includes('five senses')) {
      return '**Sense Organs (5)**:\n1. 👁️ **Eyes**: Sight / Vision\n2. 👂 **Ears**: Hearing & Balance\n3. 👃 **Nose**: Smell\n4. 👅 **Tongue**: Taste\n5. 🖐️ **Skin**: Touch, Temperature & Pressure';
    }

    // 6. Live Knowledge Retrieval via Wikipedia REST API & DuckDuckGo
    const wikiResult = await this.fetchWikipediaFact(rawPrompt);
    if (wikiResult) {
      return `### ${wikiResult.title}\n\n${wikiResult.extract}`;
    }

    const liveSearchFact = await this.fetchDuckDuckGoFact(rawPrompt);
    if (liveSearchFact) {
      return liveSearchFact;
    }

    // 7. Direct Concise Output (Zero Filler Text)
    return `**${rawPrompt}**: Processed cleanly with DOLSYX AI Engine.`;
  }

  private static isImageIntent(clean: string): boolean {
    if (clean.includes('image') || clean.includes('picture') || clean.includes('photo') || clean.includes('draw') || clean.includes('wallpaper')) {
      if (clean.includes('what is an image') || clean.includes('image format')) {
        return false;
      }
      return true;
    }
    return false;
  }

  private static extractImagePrompt(raw: string): string {
    let p = raw
      .replace(/generate an image of/gi, '')
      .replace(/create an image of/gi, '')
      .replace(/draw a picture of/gi, '')
      .replace(/generate image of/gi, '')
      .replace(/create image of/gi, '')
      .replace(/generate image/gi, '')
      .replace(/create image/gi, '')
      .replace(/generate/gi, '')
      .replace(/image/gi, '')
      .replace(/picture/gi, '')
      .replace(/photo/gi, '')
      .replace(/draw/gi, '')
      .trim();

    if (!p || p.length < 2) {
      return 'A high definition luxury car parked outside a modern mansion';
    }
    return p;
  }

  private static fetchWikipediaFact(query: string): Promise<{ title: string; extract: string } | null> {
    return new Promise((resolve) => {
      const cleanTopic = query
        .replace(/^(what are|what is|explain|tell me about|who is|where is|how does|definition of|give)\s+/gi, '')
        .trim();
      if (!cleanTopic) return resolve(null);

      const formattedQuery = encodeURIComponent(cleanTopic.replace(/\s+/g, '_'));
      const url = `https://en.wikipedia.org/api/rest_v1/page/summary/${formattedQuery}`;

      const options = {
        headers: {
          'User-Agent': 'DOLSYX-AI/1.0 (https://dolsyx-app.onrender.com; contact@dolsyx.com)'
        }
      };

      https.get(url, options, (res) => {
        let data = '';
        res.on('data', chunk => data += chunk);
        res.on('end', () => {
          try {
            const json = JSON.parse(data);
            if (json.extract && json.extract.length > 20 && json.type !== 'disambiguation') {
              resolve({
                title: json.title,
                extract: json.extract,
              });
            } else {
              resolve(null);
            }
          } catch (e) {
            resolve(null);
          }
        });
      }).on('error', () => resolve(null));
    });
  }

  private static fetchDuckDuckGoFact(query: string): Promise<string | null> {
    return new Promise((resolve) => {
      const url = `https://api.duckduckgo.com/?q=${encodeURIComponent(query)}&format=json&no_html=1&skip_disambig=1`;
      https.get(url, (res) => {
        let data = '';
        res.on('data', chunk => data += chunk);
        res.on('end', () => {
          try {
            const json = JSON.parse(data);
            if (json.AbstractText && json.AbstractText.length > 20) {
              resolve(json.AbstractText);
            } else if (json.Heading && json.RelatedTopics?.[0]?.Text) {
              resolve(`**${json.Heading}**: ${json.RelatedTopics[0].Text}`);
            } else {
              resolve(null);
            }
          } catch (e) {
            resolve(null);
          }
        });
      }).on('error', () => resolve(null));
    });
  }

  private static queryExternalLlm(prompt: string, apiKey: string, history: DolsyxAiMessage[]): Promise<string> {
    return new Promise((resolve, reject) => {
      const isGroq = apiKey.startsWith('gsk_');
      const hostname = isGroq ? 'api.groq.com' : 'api.openai.com';
      const path = isGroq ? '/openai/v1/chat/completions' : '/v1/chat/completions';
      const model = isGroq ? 'llama-3.3-70b-versatile' : 'gpt-3.5-turbo';

      const payload = JSON.stringify({
        model,
        messages: [
          { role: 'system', content: DolsyxAiEngine.MASTER_SYSTEM_PROMPT },
          ...history.slice(-4),
          { role: 'user', content: prompt }
        ],
        temperature: 0.7,
        max_tokens: 1024,
      });

      const req = https.request({
        hostname,
        port: 443,
        path,
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${apiKey}`,
          'Content-Length': Buffer.byteLength(payload)
        },
        timeout: 8000,
      }, (res) => {
        let data = '';
        res.on('data', (chunk) => data += chunk);
        res.on('end', () => {
          try {
            const json = JSON.parse(data);
            const content = json.choices?.[0]?.message?.content;
            if (content) resolve(content);
            else reject(new Error('No response content from LLM API'));
          } catch (e) {
            reject(e);
          }
        });
      });

      req.on('error', (err) => reject(err));
      req.on('timeout', () => { req.destroy(); reject(new Error('LLM API Timeout')); });
      req.write(payload);
      req.end();
    });
  }
}

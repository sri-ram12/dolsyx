export class AISafetyLayer {
  private static readonly INJECTION_PATTERNS = [
    /\b(ignore\s+(all\s+)?(previous|prior)\s+instructions)\b/i,
    /\b(disregard\s+(all\s+)?(previous|prior)\s+rules)\b/i,
    /\b(you\s+are\s+now\s+in\s+developer\s+mode)\b/i,
    /\b(bypass\s+(system|safety|security)\s+filters)\b/i,
    /\b(reveal\s+(internal|system)\s+prompt)\b/i,
    /\b(print\s+(system|developer)\s+instructions)\b/i,
    /\b(show\s+me\s+the\s+hidden\s+prompt)\b/i,
    /\b(leak\s+(private|user)\s+keys)\b/i,
  ];

  /**
   * Evaluates input prompt for potential injection or security violations.
   * Returns a sanitized prompt or throws/flags if high severity violation.
   */
  public static validateInput(prompt: string): { isSafe: boolean; flaggedReason?: string; sanitized: string } {
    if (!prompt || typeof prompt !== 'string') {
      return { isSafe: false, flaggedReason: 'Empty or invalid prompt', sanitized: '' };
    }

    const trimmed = prompt.trim();
    if (trimmed.length > 30000) {
      return { isSafe: false, flaggedReason: 'Prompt exceeds maximum permissible length (30,000 characters)', sanitized: trimmed.slice(0, 30000) };
    }

    for (const pattern of this.INJECTION_PATTERNS) {
      if (pattern.test(trimmed)) {
        return {
          isSafe: true, // We allow processing but append protective guidance rather than hard failing, ensuring natural deflection
          flaggedReason: 'Potential adversarial injection attempt detected',
          sanitized: trimmed,
        };
      }
    }

    return { isSafe: true, sanitized: trimmed };
  }

  /**
   * Sanitizes output text to prevent leaking server tokens, passwords or secrets.
   */
  public static sanitizeOutput(output: string): string {
    if (!output) return '';
    let clean = output;

    // Redact potential JWT tokens
    clean = clean.replace(/eyJ[a-zA-Z0-9_\-]{10,}\.[a-zA-Z0-9_\-]{10,}\.[a-zA-Z0-9_\-]{10,}/g, '[REDACTED_AUTH_TOKEN]');

    // Redact standard DB connection URIs
    clean = clean.replace(/postgres(?:ql)?:\/\/[^:\s]+:[^@\s]+@[^\s/]+/gi, 'postgresql://[USER]:[PASSWORD]@[HOST]');

    return clean;
  }
}

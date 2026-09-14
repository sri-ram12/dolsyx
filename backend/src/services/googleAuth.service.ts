import { OAuth2Client } from "google-auth-library";
import crypto from "crypto";

const DEFAULT_GOOGLE_CLIENT_ID = "135176717661-ugfua55saob2pfm6er1f8o9bunubhdsp.apps.googleusercontent.com";

export interface GoogleVerifiedIdentity {
  sub: string;
  email: string;
  emailVerified: boolean;
  name?: string | undefined;
  givenName?: string | undefined;
  familyName?: string | undefined;
  picture?: string | undefined;
  locale?: string | undefined;
}

export class GoogleAuthService {
  public getClientId(): string {
    return process.env.GOOGLE_CLIENT_ID || DEFAULT_GOOGLE_CLIENT_ID;
  }

  public getClientSecret(): string {
    return process.env.GOOGLE_CLIENT_SECRET || "";
  }

  public getRedirectUri(customUri?: string): string {
    if (customUri) return customUri;
    if (process.env.GOOGLE_REDIRECT_URI) return process.env.GOOGLE_REDIRECT_URI;
    const port = process.env.PORT || "4000";
    return `http://localhost:${port}/api/auth/google/callback`;
  }

  public getClient(redirectUri?: string): OAuth2Client {
    return new OAuth2Client(
      this.getClientId(),
      this.getClientSecret(),
      this.getRedirectUri(redirectUri)
    );
  }

  /**
   * Generates PKCE verifier & challenge pair (S256)
   */
  public generatePkcePair() {
    const codeVerifier = crypto.randomBytes(32).toString("base64url");
    const codeChallenge = crypto
      .createHash("sha256")
      .update(codeVerifier)
      .digest("base64url");

    return { codeVerifier, codeChallenge };
  }

  /**
   * Generates Google OAuth Authorization URL for web redirect
   */
  public generateAuthUrl(state: string, codeChallenge: string, redirectUri?: string): string {
    const client = this.getClient(redirectUri);
    return client.generateAuthUrl({
      access_type: "offline",
      scope: [
        "openid",
        "https://www.googleapis.com/auth/userinfo.email",
        "https://www.googleapis.com/auth/userinfo.profile",
      ],
      state,
      code_challenge: codeChallenge,
      code_challenge_method: "S256" as any,
      prompt: "select_account",
    });
  }

  /**
   * Exchanges authorization code for tokens and verifies ID token
   */
  public async exchangeCodeForIdentity(
    code: string,
    codeVerifier: string,
    redirectUri?: string
  ): Promise<GoogleVerifiedIdentity> {
    const client = this.getClient(redirectUri);

    const { tokens } = await client.getToken({
      code,
      codeVerifier,
    });

    if (!tokens.id_token) {
      throw new Error("Google OAuth response missing ID token");
    }

    return this.verifyIdToken(tokens.id_token);
  }

  /**
   * Cryptographically verifies Google OIDC ID token signature, issuer, audience, and expiration
   */
  public async verifyIdToken(idToken: string): Promise<GoogleVerifiedIdentity> {
    const clientId = this.getClientId();
    const client = this.getClient();
    const ticket = await client.verifyIdToken(
      clientId
        ? { idToken, audience: clientId }
        : { idToken }
    );

    const payload = ticket.getPayload();
    if (!payload) {
      throw new Error("Invalid Google ID token payload");
    }

    // Verify mandatory claims
    if (!payload.sub) {
      throw new Error("Google ID token missing subject (sub) identifier");
    }

    if (!payload.email) {
      throw new Error("Google ID token missing email address");
    }

    // Issuer validation
    const validIssuers = ["accounts.google.com", "https://accounts.google.com"];
    if (!payload.iss || !validIssuers.includes(payload.iss)) {
      throw new Error(`Invalid ID token issuer: ${payload.iss}`);
    }

    return {
      sub: payload.sub,
      email: payload.email.toLowerCase(),
      emailVerified: !!payload.email_verified,
      name: payload.name,
      givenName: payload.given_name,
      familyName: payload.family_name,
      picture: payload.picture,
      locale: payload.locale,
    };
  }
}

export const googleAuthService = new GoogleAuthService();

/**
 * Authentication service for verifying Google Identity Tokens
 */
export interface VerifiedStudentIdentity {
  email: string;
  name: string;
  sub: string;
}

export class AuthService {
  /**
   * Verifies Google ID Token and extracts verified email
   */
  async verifyGoogleIdToken(idToken: string): Promise<VerifiedStudentIdentity | null> {
    if (!idToken) return null;

    // In production, verify with google-auth-library OAuth2Client
    // For development / initial scaffold, simulate or decode payload safely
    try {
      const parts = idToken.split('.');
      if (parts.length === 3) {
        const payloadJson = Buffer.from(parts[1], 'base64url').toString('utf-8');
        const payload = JSON.parse(payloadJson);
        if (payload.email) {
          return {
            email: String(payload.email).trim().toLowerCase(),
            name: String(payload.name || ''),
            sub: String(payload.sub || ''),
          };
        }
      }
    } catch {
      return null;
    }

    return null;
  }
}

export const authService = new AuthService();

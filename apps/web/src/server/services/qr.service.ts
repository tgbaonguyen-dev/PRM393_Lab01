import crypto from 'crypto';
import { QRTokenPayload } from '@/types/domain';

export class QRService {
  private readonly secretKey: string;
  private readonly validityDurationMs = 15000; // 15 seconds rotation

  constructor(secretKey?: string) {
    this.secretKey = secretKey || process.env.QR_HMAC_SECRET || 'default-dev-secret-key-prm393';
  }

  /**
   * Generates a signed QR token valid for 15 seconds
   */
  generateToken(windowId: string, lessonId: string): { token: string; expiresAt: number } {
    const timestamp = Date.now();
    const expiresAt = timestamp + this.validityDurationMs;
    const nonce = crypto.randomBytes(8).toString('hex');

    const payload: QRTokenPayload = {
      windowId,
      lessonId,
      timestamp,
      expiresAt,
      nonce,
    };

    const payloadString = JSON.stringify(payload);
    const signature = crypto
      .createHmac('sha256', this.secretKey)
      .update(payloadString)
      .digest('hex');

    // Base64Url encode payload.signature
    const token = `${Buffer.from(payloadString).toString('base64url')}.${signature}`;

    return { token, expiresAt };
  }

  /**
   * Validates a signed QR token and checks for expiry
   */
  validateToken(token: string): { isValid: boolean; payload?: QRTokenPayload; error?: string } {
    try {
      const [encodedPayload, receivedSignature] = token.split('.');
      if (!encodedPayload || !receivedSignature) {
        return { isValid: false, error: 'Invalid token structure' };
      }

      const payloadString = Buffer.from(encodedPayload, 'base64url').toString('utf-8');
      const expectedSignature = crypto
        .createHmac('sha256', this.secretKey)
        .update(payloadString)
        .digest('hex');

      // Timing-safe signature check
      const sigMatch = crypto.timingSafeEqual(
        Buffer.from(receivedSignature),
        Buffer.from(expectedSignature)
      );

      if (!sigMatch) {
        return { isValid: false, error: 'Invalid QR signature' };
      }

      const payload: QRTokenPayload = JSON.parse(payloadString);
      const now = Date.now();

      if (now > payload.expiresAt) {
        return { isValid: false, error: 'QR token expired. Please rescan current QR.' };
      }

      return { isValid: true, payload };
    } catch {
      return { isValid: false, error: 'Failed to decode QR token' };
    }
  }
}

export const qrService = new QRService();

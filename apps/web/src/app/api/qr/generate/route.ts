import { NextRequest, NextResponse } from 'next/server';
import { qrService } from '@/server/services/qr.service';

/**
 * Controller: POST /api/qr/generate
 * Generates a signed 15-second rotating QR token for an active attendance window
 */
export async function POST(req: NextRequest) {
  try {
    const body = await req.json();
    const { windowId, lessonId } = body;

    if (!windowId || !lessonId) {
      return NextResponse.json(
        { error: 'Missing windowId or lessonId' },
        { status: 400 }
      );
    }

    const { token, expiresAt } = qrService.generateToken(windowId, lessonId);

    return NextResponse.json({
      success: true,
      token,
      expiresAt,
      rotationIntervalSeconds: 15,
    });
  } catch (err: unknown) {
    const errorMsg = err instanceof Error ? err.message : 'Internal Server Error';
    return NextResponse.json({ error: errorMsg }, { status: 500 });
  }
}

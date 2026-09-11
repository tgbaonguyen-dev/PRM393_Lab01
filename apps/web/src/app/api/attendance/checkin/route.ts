import { NextRequest, NextResponse } from 'next/server';
import { authService } from '@/server/services/auth.service';
import { attendanceService } from '@/server/services/attendance.service';

/**
 * Controller: POST /api/attendance/checkin
 * Validates Google ID token and checks in student
 */
export async function POST(req: NextRequest) {
  try {
    const body = await req.json();
    const { qrToken, googleIdToken, clientEmail } = body;

    if (!qrToken) {
      return NextResponse.json({ error: 'Mã QR không được để trống' }, { status: 400 });
    }

    // Authenticate student via Google ID Token
    let verifiedEmail = '';
    if (googleIdToken) {
      const identity = await authService.verifyGoogleIdToken(googleIdToken);
      if (identity) {
        verifiedEmail = identity.email;
      }
    } else if (process.env.NODE_ENV === 'development' && clientEmail) {
      // Allow dev test fallback if explicitly running in development
      verifiedEmail = clientEmail;
    }

    if (!verifiedEmail) {
      return NextResponse.json(
        { error: 'Xác thực tài khoản Google không thành công.' },
        { status: 401 }
      );
    }

    // Forward to Dart Shelf Backend (Port 8080)
    const dartRes = await fetch('http://localhost:8080/api/attendance/checkin', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        qrToken,
        clientEmail: verifiedEmail,
      }),
    });

    const result = await dartRes.json();
    return NextResponse.json(result, { status: dartRes.status });
  } catch (err: unknown) {
    const errorMsg = err instanceof Error ? err.message : 'Lỗi xử lý điểm danh';
    return NextResponse.json({ error: errorMsg }, { status: 500 });
  }
}

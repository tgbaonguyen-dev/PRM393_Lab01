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

    // Process check-in business rules
    const result = await attendanceService.processCheckIn(qrToken, verifiedEmail);

    return NextResponse.json(
      { success: result.success, message: result.message },
      { status: result.statusCode }
    );
  } catch (err: unknown) {
    const errorMsg = err instanceof Error ? err.message : 'Lỗi xử lý điểm danh';
    return NextResponse.json({ error: errorMsg }, { status: 500 });
  }
}

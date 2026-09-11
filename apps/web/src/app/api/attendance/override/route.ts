import { NextRequest, NextResponse } from 'next/server';
import { attendanceService } from '@/server/services/attendance.service';

/**
 * Controller: POST /api/attendance/override
 * Allows lecturer to manually override a student's result to A or P
 */
export async function POST(req: NextRequest) {
  try {
    const body = await req.json();
    const { lessonId, studentEmail, status } = body;

    if (!lessonId || !studentEmail || !status) {
      return NextResponse.json(
        { error: 'Missing required parameters (lessonId, studentEmail, status)' },
        { status: 400 }
      );
    }

    if (status !== 'A' && status !== 'P') {
      return NextResponse.json({ error: 'Status must be A or P' }, { status: 400 });
    }

    const ok = await attendanceService.applyManualOverride(lessonId, studentEmail, status);

    return NextResponse.json({ success: ok });
  } catch (err: unknown) {
    const errorMsg = err instanceof Error ? err.message : 'Error overriding attendance';
    return NextResponse.json({ error: errorMsg }, { status: 500 });
  }
}

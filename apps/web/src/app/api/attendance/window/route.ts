import { NextRequest, NextResponse } from 'next/server';
import { attendanceService } from '@/server/services/attendance.service';

/**
 * Controller: POST /api/attendance/window
 * Manages attendance window lifecycle: open, close, reopen
 */
export async function POST(req: NextRequest) {
  try {
    const body = await req.json();
    const { action, lessonId, windowId } = body;

    if (action === 'open') {
      if (!lessonId) {
        return NextResponse.json({ error: 'Missing lessonId' }, { status: 400 });
      }
      const window = await attendanceService.openWindow(lessonId);
      return NextResponse.json({ success: true, window });
    }

    if (action === 'close') {
      if (!windowId) {
        return NextResponse.json({ error: 'Missing windowId' }, { status: 400 });
      }
      const closed = await attendanceService.closeWindow(windowId);
      return NextResponse.json({ success: closed });
    }

    return NextResponse.json({ error: 'Unsupported action' }, { status: 400 });
  } catch (err: unknown) {
    const errorMsg = err instanceof Error ? err.message : 'Error managing window';
    return NextResponse.json({ error: errorMsg }, { status: 500 });
  }
}

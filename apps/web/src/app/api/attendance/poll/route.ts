import { NextRequest, NextResponse } from 'next/server';
import { attendanceService } from '@/server/services/attendance.service';

/**
 * Controller: GET /api/attendance/poll?lessonId=...
 * Serves 5-second desktop polling for live attendance results (FR-11)
 */
export async function GET(req: NextRequest) {
  try {
    const { searchParams } = new URL(req.url);
    const lessonId = searchParams.get('lessonId');

    if (!lessonId) {
      return NextResponse.json({ error: 'Missing lessonId query parameter' }, { status: 400 });
    }

    const results = await attendanceService.getPollResults(lessonId);

    const presentCount = results.filter((r) => r.status === 'P').length;
    const absentCount = results.filter((r) => r.status === 'A').length;

    return NextResponse.json({
      success: true,
      lessonId,
      presentCount,
      absentCount,
      total: results.length,
      results,
    });
  } catch (err: unknown) {
    const errorMsg = err instanceof Error ? err.message : 'Error polling results';
    return NextResponse.json({ error: errorMsg }, { status: 500 });
  }
}

import { NextRequest, NextResponse } from 'next/server';
import { dataGatewayRepository } from '@/server/repositories/data-gateway.repository';

/**
 * Controller: POST /api/class/sync
 * Syncs classes, Overview, and per-class Markbooks to Google Sheets
 */
export async function POST(req: NextRequest) {
  try {
    const body = await req.json();
    const { classes, startDate, offering, roster, lessons } = body;

    // 1. Batch sync of all classes from desktop with custom start date
    if (classes && Array.isArray(classes)) {
      const result = await dataGatewayRepository.syncAllClasses(classes, startDate || '');
      return NextResponse.json({
        success: result.success,
        spreadsheetUrl: result.spreadsheetUrl,
        message: 'Đã đồng bộ toàn bộ các lớp học lên Google Sheet thành công.',
      });
    }

    // 2. Single class offering sync fallback
    if (offering && roster) {
      const success = await dataGatewayRepository.saveClassOffering(offering, roster, lessons || []);
      return NextResponse.json({ success, message: 'Class offering synced to Google Sheets successfully.' });
    }

    return NextResponse.json({ error: 'Missing classes or offering data' }, { status: 400 });
  } catch (err: unknown) {
    const errorMsg = err instanceof Error ? err.message : 'Error syncing class offering';
    return NextResponse.json({ error: errorMsg }, { status: 500 });
  }
}

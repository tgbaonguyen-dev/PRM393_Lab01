import { NextResponse } from 'next/server';

export async function GET() {
  return NextResponse.json({
    status: 'ok',
    service: 'PRM393 Attendance API',
    timestamp: new Date().toISOString(),
  });
}

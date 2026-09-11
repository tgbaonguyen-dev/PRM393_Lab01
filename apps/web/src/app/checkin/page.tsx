'use client';

import React, { useState, Suspense } from 'react';
import { useSearchParams } from 'next/navigation';

function CheckInForm() {
  const searchParams = useSearchParams();
  const token = searchParams.get('token') || '';

  const [isLoading, setIsLoading] = useState(false);
  const [statusMessage, setStatusMessage] = useState<string | null>(null);
  const [isSuccess, setIsSuccess] = useState<boolean | null>(null);
  const [devEmail, setDevEmail] = useState('');

  const effectiveMessage =
    statusMessage || (!token ? 'Không tìm thấy mã QR. Vui lòng quét lại mã từ màn hình của giảng viên.' : null);
  const effectiveIsSuccess =
    isSuccess !== null ? isSuccess : (!token ? false : null);

  const handleCheckIn = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!token) return;

    setIsLoading(true);
    setStatusMessage(null);

    try {
      const res = await fetch('/api/attendance/checkin', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          qrToken: token,
          clientEmail: devEmail,
        }),
      });

      const data = await res.json();
      setIsSuccess(res.ok);
      setStatusMessage(data.message || data.error || 'Xử lý hoàn tất.');
    } catch {
      setIsSuccess(false);
      setStatusMessage('Lỗi kết nối máy chủ. Vui lòng thử lại.');
    } finally {
      setIsLoading(false);
    }
  };

  return (
    <div className="w-full max-w-md bg-white rounded-2xl shadow-xl p-6 border border-slate-100">
      <div className="text-center mb-6">
        <div className="inline-flex items-center justify-center w-14 h-14 rounded-full bg-blue-100 text-blue-600 mb-3">
          <svg className="w-8 h-8" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z" />
          </svg>
        </div>
        <h1 className="text-2xl font-bold text-slate-800">Điểm danh PRM393</h1>
        <p className="text-sm text-slate-500 mt-1">Cổng điểm danh sinh viên bằng mã QR</p>
      </div>

      {effectiveMessage && (
        <div
          className={`p-4 rounded-xl mb-6 text-sm font-medium ${
            effectiveIsSuccess
              ? 'bg-emerald-50 text-emerald-800 border border-emerald-200'
              : 'bg-rose-50 text-rose-800 border border-rose-200'
          }`}
        >
          {effectiveMessage}
        </div>
      )}

      <form onSubmit={handleCheckIn} className="space-y-4">
        <div>
          <label className="block text-sm font-medium text-slate-700 mb-1">
            Email sinh viên (Google Account)
          </label>
          <input
            type="email"
            required
            value={devEmail}
            onChange={(e) => setDevEmail(e.target.value)}
            placeholder="ten.mssv@fpt.edu.vn"
            className="w-full px-4 py-2.5 rounded-xl border border-slate-300 focus:outline-none focus:ring-2 focus:ring-blue-500 text-slate-900"
          />
        </div>

        <button
          type="submit"
          disabled={isLoading || !token}
          className="w-full py-3 px-4 bg-blue-600 hover:bg-blue-700 disabled:bg-slate-300 text-white font-semibold rounded-xl transition duration-200 shadow-sm"
        >
          {isLoading ? 'Đang xác nhận...' : 'Xác nhận Điểm danh'}
        </button>
      </form>

      <div className="mt-6 text-center text-xs text-slate-400">
        Mã QR xoay vòng mỗi 15 giây. Nếu hết hạn, vui lòng quét lại.
      </div>
    </div>
  );
}

export default function StudentCheckInPage() {
  return (
    <main className="min-h-screen bg-slate-50 flex items-center justify-center p-4">
      <Suspense fallback={<div className="text-slate-500">Đang tải...</div>}>
        <CheckInForm />
      </Suspense>
    </main>
  );
}

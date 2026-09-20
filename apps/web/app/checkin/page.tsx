'use client';

import { Suspense, useCallback, useEffect, useRef, useState } from 'react';
import { useSearchParams } from 'next/navigation';
import GoogleSignInButton from '../../components/GoogleSignInButton';

type Status =
  | 'idle'
  | 'loading'
  | 'success'
  | 'already'
  | 'expired'
  | 'roster'
  | 'closed'
  | 'auth'
  | 'manual'
  | 'persistence'
  | 'error';

type ApiResponse = {
  success?: boolean;
  status?: string;
  message?: string;
  data?: { email?: string; studentName?: string; status?: string };
};

const rawApiUrl = (process.env.NEXT_PUBLIC_API_BASE_URL ?? 'http://localhost:8080').trim();
const apiBaseUrl = (rawApiUrl.startsWith('http://') || rawApiUrl.startsWith('https://')
  ? rawApiUrl
  : `https://${rawApiUrl}`).replace(/\/$/, '');

function statusFromApi(result: ApiResponse): Status {
  switch (result.status) {
    case 'SUCCESS': return 'success';
    case 'ALREADY_CHECKED_IN': return 'already';
    case 'QR_EXPIRED':
    case 'INVALID_QR': return 'expired';
    case 'NOT_IN_ROSTER': return 'roster';
    case 'SESSION_CLOSED': return 'closed';
    case 'AUTH_FAILED': return 'auth';
    case 'MANUAL_OVERRIDE': return 'manual';
    case 'PERSISTENCE_ERROR': return 'persistence';
    default: return result.success ? 'success' : 'error';
  }
}

function CheckinContent() {
  const params = useSearchParams();
  const token = params.get('token') ?? params.get('qrToken') ?? '';
  const classId = params.get('classId') ?? '';
  const sessionId = params.get('sessionId') ?? '';
  const [idToken, setIdToken] = useState<string | null>(() =>
    typeof window === 'undefined'
      ? null
      : window.sessionStorage.getItem('prm393.googleIdToken'),
  );
  const [status, setStatus] = useState<Status>('idle');
  const [message, setMessage] = useState('Đăng nhập Google để xác thực danh tính sinh viên.');
  const [email, setEmail] = useState<string | undefined>();
  const lastAttempt = useRef('');

  const submitCheckin = useCallback(async (googleToken: string) => {
    if (!token || !classId || !sessionId) return;
    const attempt = `${googleToken}:${token}:${sessionId}:${classId}`;
    if (lastAttempt.current === attempt) return;
    lastAttempt.current = attempt;
    setStatus('loading');
    setMessage('Đang xác thực và ghi nhận điểm danh...');

    try {
      const response = await fetch(`${apiBaseUrl}/attendance/checkin`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ idToken: googleToken, qrToken: token, sessionId, classId }),
      });
      const result = (await response.json()) as ApiResponse;
      const nextStatus = statusFromApi(result);
      if (nextStatus === 'auth') {
        window.sessionStorage.removeItem('prm393.googleIdToken');
        setIdToken(null);
        lastAttempt.current = '';
      }
      setStatus(nextStatus);
      setMessage(result.message ?? 'Máy chủ đã phản hồi.');
      setEmail(result.data?.email);
    } catch {
      setStatus('error');
      setMessage('Không thể kết nối máy chủ. Vui lòng thử lại.');
    }
  }, [classId, sessionId, token]);

  useEffect(() => {
    if (idToken) {
      queueMicrotask(() => void submitCheckin(idToken));
    }
  }, [idToken, submitCheckin]);

  const handleGoogleSuccess = (googleToken: string) => {
    window.sessionStorage.setItem('prm393.googleIdToken', googleToken);
    setIdToken(googleToken);
  };

  const resetGoogleSession = () => {
    window.sessionStorage.removeItem('prm393.googleIdToken');
    setIdToken(null);
    setEmail(undefined);
    setStatus('idle');
    setMessage('Đăng nhập bằng tài khoản Google thuộc lớp học phần.');
    lastAttempt.current = '';
  };

  const retry = () => {
    lastAttempt.current = '';
    if (idToken) void submitCheckin(idToken);
    else setStatus('idle');
  };

  const statusStyle: Record<Status, string> = {
    idle: 'border-[#d6ddd2] bg-white',
    loading: 'border-[#d6ddd2] bg-white',
    success: 'border-[#9dc9a6] bg-[#edf8ef]',
    already: 'border-[#e5c77c] bg-[#fff8e3]',
    expired: 'border-[#e6b1a0] bg-[#fff0eb]',
    roster: 'border-[#e6b1a0] bg-[#fff0eb]',
    closed: 'border-[#c7cbc7] bg-[#eef0ed]',
    auth: 'border-[#e6b1a0] bg-[#fff0eb]',
    manual: 'border-[#e5c77c] bg-[#fff8e3]',
    persistence: 'border-[#e6b1a0] bg-[#fff0eb]',
    error: 'border-[#e6b1a0] bg-[#fff0eb]',
  };

  const heading = {
    idle: 'Xác thực danh tính', loading: 'Đang xử lý', success: 'Điểm danh thành công',
    already: 'Đã điểm danh trước đó', expired: 'QR đã hết hạn', roster: 'Không thuộc danh sách lớp',
    closed: 'Phiên điểm danh đã đóng', auth: 'Xác thực Google thất bại',
    manual: 'Kết quả đã được giảng viên chỉnh sửa',
    persistence: 'Chưa thể lưu điểm danh', error: 'Không thể hoàn tất',
  }[status];

  return (
    <main className="min-h-screen px-3 py-5 text-base sm:grid sm:px-4 sm:py-8 sm:place-items-center">
      <section className="mx-auto w-full max-w-lg overflow-hidden rounded-[2rem] border border-[#dce3d8] bg-[#fbfcf8] shadow-[0_24px_70px_rgba(43,66,48,0.14)]">
        <header className="bg-[#173d2b] px-5 pb-6 pt-7 text-[#f5f6ef] sm:px-6 sm:pb-7 sm:pt-8">
          <p className="text-[11px] uppercase tracking-[0.2em] text-[#b9d6bd] sm:text-xs sm:tracking-[0.24em]">PRM393 · Student check-in</p>
          <h1 className="mt-3 text-3xl leading-tight sm:text-4xl">Một lần quét,<br />một lần có mặt.</h1>
          <div className="mt-5 grid grid-cols-1 gap-2 text-sm sm:mt-6 sm:grid-cols-2 sm:gap-3">
            <div className="min-w-0 rounded-xl bg-white/10 p-3"><span className="block text-xs text-[#b9d6bd]">Lớp học phần</span><span className="break-words">{classId || 'Chưa có'}</span></div>
            <div className="min-w-0 rounded-xl bg-white/10 p-3"><span className="block text-xs text-[#b9d6bd]">Phiên</span><span className="break-words">{sessionId || 'Chưa có'}</span></div>
          </div>
        </header>

        <div className={`m-3 rounded-2xl border p-4 sm:m-4 sm:p-5 ${statusStyle[status]}`}>
          <div className="flex items-start gap-3">
            <span className="mt-1 text-2xl" aria-hidden="true">
              {status === 'success' ? '✓' : status === 'already' || status === 'manual' ? '!' : status === 'loading' ? '…' : status === 'closed' ? '×' : '•'}
            </span>
            <div>
              <h2 className="break-words text-lg font-bold">{heading}</h2>
              <p className="mt-1 text-sm leading-6 text-[#5e6c61]">{message}</p>
              {email && <p className="mt-3 text-xs text-[#5e6c61]">Tài khoản đã xác thực: <strong>{email}</strong></p>}
            </div>
          </div>

          {!token && <p className="mt-5 rounded-xl bg-[#fff4e7] p-3 text-sm text-[#8b4d25]">Thiếu mã QR. Hãy quét mã đang hiển thị trên màn hình giảng viên.</p>}

          {status === 'idle' && token && (
            <div className="mt-6">
              <GoogleSignInButton onSuccess={handleGoogleSuccess} onError={(error) => { setStatus('auth'); setMessage(error); }} />
            </div>
          )}

          {status === 'success' && <p className="mt-5 text-center text-sm font-bold text-[#28733b]">Trạng thái đã chuyển sang P · Có mặt</p>}

          {(status === 'error' || status === 'persistence') && <button type="button" onClick={retry} className="mt-5 w-full rounded-xl bg-[#e67e43] px-4 py-3 text-sm font-bold text-white hover:bg-[#c96632]">Thử lại</button>}
          {status === 'auth' && <button type="button" onClick={resetGoogleSession} className="mt-5 w-full rounded-xl bg-[#e67e43] px-4 py-3 text-sm font-bold text-white hover:bg-[#c96632]">Đăng nhập lại</button>}
          {status === 'roster' && <button type="button" onClick={resetGoogleSession} className="mt-5 w-full rounded-xl border border-[#c9d3c7] px-4 py-3 text-sm font-bold text-[#315d3b]">Đổi tài khoản Google</button>}
        </div>

        <footer className="px-6 pb-6 text-center text-xs text-[#78847a]">Không chia sẻ đường dẫn QR khi chưa điểm danh.</footer>
      </section>
    </main>
  );
}

export default function CheckinPage() {
  return (
    <Suspense fallback={<main className="grid min-h-screen place-items-center text-sm text-[#68746b]">Đang tải trang điểm danh...</main>}>
      <CheckinContent />
    </Suspense>
  );
}

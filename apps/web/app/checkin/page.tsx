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
  const [message, setMessage] = useState('Đăng nhập tài khoản Google để xác nhận có mặt.');
  const [email, setEmail] = useState<string | undefined>();
  const lastAttempt = useRef('');

  const submitCheckin = useCallback(async (googleToken: string) => {
    if (!token || !classId || !sessionId) return;
    const attempt = `${googleToken}:${token}:${sessionId}:${classId}`;
    if (lastAttempt.current === attempt) return;
    lastAttempt.current = attempt;
    setStatus('loading');
    setMessage('Đang xác thực tài khoản và ghi nhận điểm danh...');

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
      setMessage('Không thể kết nối với máy chủ điểm danh. Vui lòng kiểm tra mạng và thử lại.');
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
    setMessage('Đăng nhập bằng tài khoản Google trường cấp (@fpt.edu.vn).');
    lastAttempt.current = '';
  };

  const retry = () => {
    lastAttempt.current = '';
    if (idToken) void submitCheckin(idToken);
    else setStatus('idle');
  };

  // Format label for Class / Session
  const displayClass = classId.replace(/^[0-9]+_/, '').replace(/_/g, ' ') || 'Chưa xác định';
  const displaySession = sessionId.includes('-L')
    ? `Slot ${sessionId.split('-L')[1]}`
    : sessionId || 'Ca hiện tại';

  return (
    <div className="relative min-h-screen bg-[#fafafa] text-neutral-900 flex flex-col justify-between px-4 py-8 sm:py-12 selection:bg-neutral-200">
      {/* Main Student Pass Container (Centered) */}
      <main className="mx-auto w-full max-w-[400px] my-auto">
        <div className="overflow-hidden rounded-2xl border border-neutral-200/90 bg-white shadow-[0_10px_35px_rgba(0,0,0,0.04)]">
          {/* Card Top: Brand Header & Course Info */}
          <div className="border-b border-neutral-100 p-6">
            <div className="flex items-center justify-between pb-4 border-b border-neutral-100">
              <div className="flex items-center gap-2">
                <div className="flex h-6 w-6 items-center justify-center rounded-md bg-neutral-900 text-white font-bold text-[11px] tracking-tight">
                  iP
                </div>
                <span className="font-semibold text-xs tracking-wider uppercase text-neutral-900">
                  iPresent
                </span>
              </div>

              <div className="inline-flex items-center gap-1.5 rounded-full border border-neutral-200 bg-neutral-50 px-2.5 py-0.5 text-[11px] font-medium text-neutral-600">
                <span className="h-1.5 w-1.5 rounded-full bg-neutral-900" />
                <span>Phiên trực tiếp</span>
              </div>
            </div>

            <div className="pt-4">
              <div className="text-[11px] font-medium uppercase tracking-wider text-neutral-400 mb-1">
                Điểm danh lớp học
              </div>
              <h1 className="text-xl sm:text-2xl font-bold tracking-tight text-neutral-900">
                {displayClass}
              </h1>

              {/* Course & Session Info Grid */}
              <div className="mt-4 grid grid-cols-2 gap-2 text-xs">
                <div className="rounded-xl border border-neutral-200/80 bg-neutral-50/50 p-2.5">
                  <div className="flex items-center gap-1.5 text-neutral-400 mb-0.5">
                    <svg className="h-3.5 w-3.5 text-neutral-500" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
                      <path d="M4 19.5A2.5 2.5 0 0 1 6.5 17H20" />
                      <path d="M6.5 2H20v20H6.5A2.5 2.5 0 0 1 4 19.5v-15A2.5 2.5 0 0 1 6.5 2z" />
                    </svg>
                    <span className="text-[10px] font-semibold uppercase tracking-wider text-neutral-400">Mã Lớp</span>
                  </div>
                  <div className="font-semibold text-neutral-800 truncate">{classId || 'Chưa rõ'}</div>
                </div>

                <div className="rounded-xl border border-neutral-200/80 bg-neutral-50/50 p-2.5">
                  <div className="flex items-center gap-1.5 text-neutral-400 mb-0.5">
                    <svg className="h-3.5 w-3.5 text-neutral-500" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
                      <circle cx="12" cy="12" r="10" />
                      <polyline points="12 6 12 12 16 14" />
                    </svg>
                    <span className="text-[10px] font-semibold uppercase tracking-wider text-neutral-400">Ca Học</span>
                  </div>
                  <div className="font-semibold text-neutral-800 truncate">{displaySession}</div>
                </div>
              </div>
            </div>
          </div>

          {/* Ticket Body: Dynamic States */}
          <div className="p-6 space-y-4">
            {/* 1. STATE: ALREADY CHECKED IN (Highlighted Monochrome Reassurance) */}
            {status === 'already' && (
              <div className="rounded-xl border border-neutral-200 bg-neutral-50/60 p-5 text-center">
                <div className="mx-auto flex h-12 w-12 items-center justify-center rounded-full bg-neutral-900 text-white shadow-xs">
                  <svg className="h-6 w-6" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round">
                    <polyline points="20 6 9 17 4 12" />
                  </svg>
                </div>

                <div className="mt-3 inline-flex items-center gap-1.5 rounded-full bg-neutral-900 text-white px-3 py-1 text-[11px] font-semibold tracking-wide">
                  <span className="h-1.5 w-1.5 rounded-full bg-white" />
                  <span>ĐÃ CÓ MẶT (P)</span>
                </div>

                <h2 className="mt-2.5 text-lg font-bold tracking-tight text-neutral-900">
                  Bạn đã điểm danh rồi
                </h2>

                <p className="mt-1.5 text-xs text-neutral-600 leading-relaxed max-w-xs mx-auto">
                  Buổi học này đã được ghi nhận có mặt từ trước. Bạn an tâm ngồi học, không cần quét lại mã QR.
                </p>

                {email && (
                  <div className="mt-4 inline-flex items-center gap-1.5 rounded-lg border border-neutral-200 bg-white px-3 py-1.5 text-xs font-mono text-neutral-800 shadow-2xs">
                    <svg className="h-3.5 w-3.5 text-neutral-500" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
                      <path d="M20 21v-2a4 4 0 0 0-4-4H8a4 4 0 0 0-4 4v2" />
                      <circle cx="12" cy="7" r="4" />
                    </svg>
                    <span>{email}</span>
                  </div>
                )}
              </div>
            )}

            {/* 2. STATE: SUCCESS */}
            {status === 'success' && (
              <div className="rounded-xl border border-neutral-200 bg-neutral-50/60 p-5 text-center">
                <div className="mx-auto flex h-12 w-12 items-center justify-center rounded-full bg-neutral-900 text-white shadow-xs">
                  <svg className="h-6 w-6" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round">
                    <polyline points="20 6 9 17 4 12" />
                  </svg>
                </div>

                <div className="mt-3 inline-flex items-center gap-1.5 rounded-full bg-neutral-900 text-white px-3 py-1 text-[11px] font-semibold tracking-wide">
                  <span className="h-1.5 w-1.5 rounded-full bg-white" />
                  <span>CÓ MẶT (P)</span>
                </div>

                <h2 className="mt-2.5 text-lg font-bold tracking-tight text-neutral-900">
                  Điểm danh thành công!
                </h2>

                <p className="mt-1.5 text-xs text-neutral-600 leading-relaxed max-w-xs mx-auto">
                  Trạng thái có mặt của bạn đã được cập nhật trực tiếp vào hệ thống chuyên cần của giảng viên.
                </p>

                {email && (
                  <div className="mt-4 inline-flex items-center gap-1.5 rounded-lg border border-neutral-200 bg-white px-3 py-1.5 text-xs font-mono text-neutral-800 shadow-2xs">
                    <svg className="h-3.5 w-3.5 text-neutral-500" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
                      <path d="M20 21v-2a4 4 0 0 0-4-4H8a4 4 0 0 0-4 4v2" />
                      <circle cx="12" cy="7" r="4" />
                    </svg>
                    <span>{email}</span>
                  </div>
                )}
              </div>
            )}

            {/* 3. STATE: LOADING */}
            {status === 'loading' && (
              <div className="rounded-xl border border-neutral-200 bg-neutral-50/50 p-6 text-center">
                <div className="mx-auto h-8 w-8 animate-spin rounded-full border-2 border-neutral-300 border-t-neutral-900" />
                <h2 className="mt-3.5 text-sm font-bold text-neutral-900">Đang ghi nhận điểm danh...</h2>
                <p className="mt-1 text-xs text-neutral-500">Đang đồng bộ trực tiếp lên hệ thống của giảng viên</p>
              </div>
            )}

            {/* 4. STATE: IDLE (WAITING FOR SIGN-IN) */}
            {status === 'idle' && (
              <div>
                {!token ? (
                  <div className="rounded-xl border border-neutral-200 bg-neutral-50/70 p-5 text-center">
                    <div className="mx-auto flex h-10 w-10 items-center justify-center rounded-full border border-neutral-200 bg-white text-neutral-800 mb-2.5 shadow-2xs">
                      <svg className="h-5 w-5" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
                        <circle cx="12" cy="12" r="10" />
                        <line x1="12" y1="8" x2="12" y2="12" />
                        <line x1="12" y1="16" x2="12.01" y2="16" />
                      </svg>
                    </div>
                    <div className="font-bold text-sm text-neutral-900">Mã QR không hợp lệ hoặc đã hết hạn</div>
                    <p className="mt-1 text-xs text-neutral-500 leading-relaxed max-w-xs mx-auto">
                      Vui lòng quét lại mã QR động đang được chiếu trực tiếp trên máy chiếu của giảng viên.
                    </p>
                  </div>
                ) : (
                  <div className="space-y-4">
                    <div className="text-center">
                      <p className="text-xs text-neutral-600 leading-relaxed">
                        Đăng nhập tài khoản Google sinh viên (<code className="rounded border border-neutral-200 bg-neutral-100 px-1.5 py-0.5 font-mono text-neutral-800 font-medium">@fpt.edu.vn</code>) để xác nhận có mặt trong lớp.
                      </p>
                    </div>

                    <div className="pt-1">
                      <GoogleSignInButton
                        onSuccess={handleGoogleSuccess}
                        onError={(err) => {
                          setStatus('auth');
                          setMessage(err);
                        }}
                      />
                    </div>

                    <div className="flex items-center justify-center gap-1.5 text-[11px] text-neutral-400">
                      <svg className="h-3.5 w-3.5" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
                        <rect x="3" y="11" width="18" height="11" rx="2" ry="2" />
                        <path d="M7 11V7a5 5 0 0 1 10 0v4" />
                      </svg>
                      <span>Bảo mật qua Google Workspace</span>
                    </div>
                  </div>
                )}
              </div>
            )}

            {/* 5. STATE: MANUAL OVERRIDE */}
            {status === 'manual' && (
              <div className="rounded-xl border border-neutral-200 bg-neutral-50 p-4 text-center">
                <div className="font-bold text-sm text-neutral-900">Đã được giảng viên điều chỉnh</div>
                <p className="mt-1 text-xs text-neutral-600">{message}</p>
              </div>
            )}

            {/* 6. STATE: ERROR / EXPIRED / ROSTER */}
            {(status === 'expired' ||
              status === 'roster' ||
              status === 'closed' ||
              status === 'auth' ||
              status === 'persistence' ||
              status === 'error') && (
              <div className="space-y-3">
                <div className="rounded-xl border border-neutral-200 bg-neutral-50 p-4">
                  <div className="flex items-start gap-3">
                    <div className="mt-0.5 flex h-5 w-5 shrink-0 items-center justify-center rounded-full bg-neutral-200 text-neutral-900 font-bold text-xs">
                      !
                    </div>
                    <div className="space-y-1">
                      <div className="font-bold text-sm text-neutral-900">
                        {status === 'expired' && 'Mã QR đã hết hạn'}
                        {status === 'roster' && 'Email không thuộc danh sách lớp'}
                        {status === 'closed' && 'Phiên điểm danh đã đóng'}
                        {status === 'auth' && 'Xác thực Google thất bại'}
                        {(status === 'persistence' || status === 'error') && 'Không thể lưu kết quả'}
                      </div>
                      <p className="text-xs text-neutral-600 leading-relaxed">{message}</p>
                    </div>
                  </div>
                </div>

                {(status === 'error' || status === 'persistence') && (
                  <button
                    type="button"
                    onClick={retry}
                    className="w-full rounded-xl bg-neutral-900 px-4 py-2.5 text-xs sm:text-sm font-semibold text-white shadow-2xs transition hover:bg-black active:scale-[0.99] cursor-pointer"
                  >
                    Thử lại
                  </button>
                )}

                {(status === 'auth' || status === 'roster') && (
                  <button
                    type="button"
                    onClick={resetGoogleSession}
                    className="w-full rounded-xl border border-neutral-300 bg-white px-4 py-2.5 text-xs sm:text-sm font-semibold text-neutral-800 shadow-2xs transition hover:bg-neutral-50 active:scale-[0.99] cursor-pointer"
                  >
                    Đăng nhập bằng tài khoản khác
                  </button>
                )}
              </div>
            )}
          </div>
        </div>
      </main>
    </div>
  );
}

export default function CheckinPage() {
  return (
    <Suspense
      fallback={
        <main className="grid min-h-screen place-items-center bg-[#fafafa] text-xs text-neutral-500">
          <div className="flex items-center gap-2">
            <div className="h-4 w-4 animate-spin rounded-full border-2 border-neutral-300 border-t-neutral-900" />
            <span>Đang tải thông tin...</span>
          </div>
        </main>
      }
    >
      <CheckinContent />
    </Suspense>
  );
}

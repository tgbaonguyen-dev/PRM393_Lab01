'use client';

import { useEffect, useRef, useState } from 'react';
import Script from 'next/script';

declare global {
  interface Window {
    google?: {
      accounts: {
        id: {
          initialize(config: {
            client_id: string;
            callback(response: { credential?: string }): void;
          }): void;
          renderButton(element: HTMLElement, options: {
            theme: 'outline' | 'filled_blue' | 'filled_black';
            size: 'large' | 'medium' | 'small';
            text: 'signin_with' | 'signup_with' | 'continue_with' | 'signin';
            shape?: 'rectangular' | 'pill' | 'circle' | 'square';
            logo_alignment?: 'left' | 'center';
            width: number;
          }): void;
        };
      };
    };
  }
}

type Props = {
  disabled?: boolean;
  onSuccess(token: string): void;
  onError(message: string): void;
};

export default function GoogleSignInButton({ disabled = false, onSuccess, onError }: Props) {
  const containerRef = useRef<HTMLDivElement>(null);
  const [loaded, setLoaded] = useState(false);
  const clientId = process.env.NEXT_PUBLIC_GOOGLE_CLIENT_ID?.trim() ?? '';
  const demoMode = process.env.NEXT_PUBLIC_DEMO_GOOGLE === 'true';
  const demoEmail = process.env.NEXT_PUBLIC_DEMO_EMAIL?.trim() || 'student@example.com';

  useEffect(() => {
    if (!loaded || !clientId || !containerRef.current || !window.google) return;

    try {
      window.google.accounts.id.initialize({
        client_id: clientId,
        callback: (response) => {
          if (response.credential) {
            onSuccess(response.credential);
          } else {
            onError('Google không trả về ID Token.');
          }
        },
      });
      containerRef.current.replaceChildren();
      const buttonWidth = Math.min(340, Math.max(260, containerRef.current.clientWidth || 320));
      window.google.accounts.id.renderButton(containerRef.current, {
        theme: 'filled_black',
        size: 'large',
        text: 'continue_with',
        shape: 'pill',
        width: buttonWidth,
      });
    } catch {
      onError('Không thể khởi tạo Google Sign-In.');
    }
  }, [clientId, loaded, onError, onSuccess]);

  if (!clientId) {
    if (demoMode) {
      return (
        <div className="w-full">
          <button
            type="button"
            disabled={disabled}
            onClick={() => onSuccess(`mock_id_token_${demoEmail}_${Date.now()}`)}
            className="group relative flex w-full items-center justify-between overflow-hidden rounded-full bg-neutral-950 px-5 py-3.5 text-sm font-medium text-white shadow-[0_4px_16px_rgba(0,0,0,0.12),inset_0_1px_0_rgba(255,255,255,0.15)] transition-all duration-200 hover:bg-black hover:shadow-[0_8px_25px_rgba(0,0,0,0.2)] hover:scale-[1.01] active:scale-[0.98] disabled:cursor-not-allowed disabled:opacity-50 cursor-pointer"
          >
            <div className="flex items-center gap-3">
              <div className="flex h-6 w-6 items-center justify-center rounded-full bg-white shadow-xs">
                <svg className="h-3.5 w-3.5" viewBox="0 0 24 24">
                  <path fill="#4285F4" d="M22.56 12.25c0-.78-.07-1.53-.2-2.25H12v4.26h5.92c-.26 1.37-1.04 2.53-2.21 3.31v2.77h3.57c2.08-1.92 3.28-4.74 3.28-8.09z"/>
                  <path fill="#34A853" d="M12 23c2.97 0 5.46-.98 7.28-2.66l-3.57-2.77c-.98.66-2.23 1.06-3.71 1.06-2.86 0-5.29-1.93-6.16-4.53H2.18v2.84C3.99 20.53 7.7 23 12 23z"/>
                  <path fill="#FBBC05" d="M5.84 14.09c-.22-.66-.35-1.36-.35-2.09s.13-1.43.35-2.09V7.07H2.18C1.43 8.55 1 10.22 1 12s.43 3.45 1.18 4.93l2.85-2.22.81-.62z"/>
                  <path fill="#EA4335" d="M12 5.38c1.62 0 3.06.56 4.21 1.64l3.15-3.15C17.45 2.09 14.97 1 12 1 7.7 1 3.99 3.47 2.18 7.07l3.66 2.84c.87-2.6 3.3-4.53 6.16-4.53z"/>
                </svg>
              </div>
              <span className="font-semibold tracking-tight text-white text-sm">Đăng nhập với Google</span>
            </div>

            <div className="flex h-6 w-6 items-center justify-center rounded-full bg-white/10 text-white/70 transition-transform duration-200 group-hover:translate-x-0.5 group-hover:bg-white/20 group-hover:text-white">
              <svg className="h-3.5 w-3.5" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round">
                <path d="M5 12h14" />
                <path d="m12 5 7 7-7 7" />
              </svg>
            </div>
          </button>
        </div>
      );
    }

    return (
      <div className="rounded-xl border border-neutral-200 bg-neutral-50 p-3.5 text-center text-xs text-neutral-600 leading-relaxed">
        Chưa cấu hình Google Client ID trên máy chủ.
      </div>
    );
  }

  return (
    <div className={`relative flex min-h-12 w-full justify-center ${disabled ? 'pointer-events-none opacity-45' : ''}`}>
      <Script
        src="https://accounts.google.com/gsi/client"
        strategy="afterInteractive"
        onLoad={() => setLoaded(true)}
        onError={() => onError('Không thể tải Google Identity Services.')}
      />
      <div
        ref={containerRef}
        className="w-full max-w-[340px] overflow-hidden rounded-full flex justify-center shadow-[0_4px_16px_rgba(0,0,0,0.1)] transition-transform duration-200 hover:scale-[1.01]"
        aria-label="Đăng nhập bằng Google"
      />
      {!loaded && (
        <span className="absolute inset-0 grid place-items-center text-xs text-neutral-400">
          Đang tải Google...
        </span>
      )}
    </div>
  );
}

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
      const buttonWidth = Math.min(320, Math.max(220, containerRef.current.clientWidth || 320));
      window.google.accounts.id.renderButton(containerRef.current, {
        theme: 'outline',
        size: 'large',
        text: 'signin_with',
        width: buttonWidth,
      });
    } catch {
      onError('Không thể khởi tạo Google Sign-In.');
    }
  }, [clientId, loaded, onError, onSuccess]);

  if (!clientId) {
    if (demoMode) {
      return (
        <div className="space-y-2">
          <button
            type="button"
            disabled={disabled}
            onClick={() => onSuccess(`mock_id_token_${demoEmail}_${Date.now()}`)}
            className="w-full rounded-xl bg-[#173d2b] px-4 py-3 text-sm font-bold text-white transition hover:bg-[#24563e] disabled:cursor-not-allowed disabled:opacity-50"
          >
            Sign in with Google
          </button>
        </div>
      );
    }

    return (
      <p className="rounded-xl border border-[#e3b27b] bg-[#fff4e7] p-3 text-center text-sm text-[#8b4d25]">
        Website chưa được cấu hình Google Client ID.
      </p>
    );
  }

  return (
    <div className={`relative flex min-h-12 justify-center ${disabled ? 'pointer-events-none opacity-45' : ''}`}>
      <Script
        src="https://accounts.google.com/gsi/client"
        strategy="afterInteractive"
        onLoad={() => setLoaded(true)}
        onError={() => onError('Không thể tải Google Identity Services.')}
      />
      <div ref={containerRef} className="w-full max-w-[320px] overflow-hidden" aria-label="Đăng nhập bằng Google" />
      {!loaded && <span className="absolute inset-0 grid place-items-center text-sm text-[#68746b]">Đang tải Google...</span>}
    </div>
  );
}

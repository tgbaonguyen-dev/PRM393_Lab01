import type { Metadata } from 'next';
import './globals.css';

export const metadata: Metadata = {
  title: 'PRM393 | Điểm danh',
  description: 'Cổng điểm danh QR dành cho sinh viên',
};

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="vi">
      <body>{children}</body>
    </html>
  );
}

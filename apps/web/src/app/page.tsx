import Link from "next/link";

export default function Home() {
  return (
    <div className="min-h-screen bg-slate-50 flex flex-col justify-between">
      {/* Navigation Header */}
      <header className="w-full bg-white border-b border-slate-200 py-4 px-6 sm:px-12 flex items-center justify-between shadow-xs">
        <div className="flex items-center gap-3">
          <div className="w-10 h-10 rounded-xl bg-linear-to-br from-blue-600 to-indigo-700 flex items-center justify-center text-white shadow-md shadow-blue-500/20">
            <svg className="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M12 4v1m6 11h2m-6 0h-2v4m0-11v3m0 0h.01M12 12h4.01M16 20h4M4 12h4m12 0h.01M5 8h2a1 1 0 001-1V5a1 1 0 00-1-1H5a1 1 0 00-1 1v2a1 1 0 001 1zm12 0h2a1 1 0 001-1V5a1 1 0 00-1-1h-2a1 1 0 00-1 1v2a1 1 0 001 1zM5 20h2a1 1 0 001-1v-2a1 1 0 00-1-1H5a1 1 0 00-1 1v2a1 1 0 001 1z" />
            </svg>
          </div>
          <div>
            <h1 className="text-base font-bold text-slate-900 leading-tight">PRM393 Attendance</h1>
            <p className="text-xs text-slate-500 font-medium">Cổng Điểm Danh Sinh Viên</p>
          </div>
        </div>

        <div className="flex items-center gap-2">
          <span className="inline-flex items-center gap-1.5 px-3 py-1 rounded-full text-xs font-semibold bg-emerald-50 text-emerald-700 border border-emerald-200">
            <span className="w-2 h-2 rounded-full bg-emerald-500 animate-pulse"></span>
            Hệ thống đang hoạt động
          </span>
        </div>
      </header>

      {/* Main Hero Section */}
      <main className="flex-1 max-w-4xl mx-auto w-full px-6 py-12 flex flex-col items-center justify-center text-center">
        <div className="inline-flex items-center gap-2 px-3 py-1 rounded-full text-xs font-semibold bg-blue-50 text-blue-700 border border-blue-200 mb-6">
          <span className="text-blue-600">✦</span> Học kỳ Fall 2026 • FPT University
        </div>

        <h2 className="text-3xl sm:text-4xl font-extrabold text-slate-900 tracking-tight mb-4">
          Hệ Thống Điểm Danh Trực Tiếp Bằng Mã QR
        </h2>
        <p className="text-base sm:text-lg text-slate-600 max-w-2xl mb-8 leading-relaxed">
          Dành cho sinh viên tham gia lớp học môn PRM393. Quét mã QR xoay vòng 15 giây từ màn hình máy chiếu của giảng viên để xác nhận có mặt trong buổi học.
        </p>

        {/* Action Buttons */}
        <div className="flex flex-col sm:flex-row items-center gap-4 mb-12 w-full max-w-md">
          <Link
            href="/checkin"
            className="w-full sm:flex-1 py-3.5 px-6 rounded-xl bg-blue-600 hover:bg-blue-700 text-white font-bold text-sm shadow-md shadow-blue-600/30 hover:shadow-lg transition-all duration-200 flex items-center justify-center gap-2"
          >
            <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M12 4v1m6 11h2m-6 0h-2v4m0-11v3m0 0h.01M12 12h4.01M16 20h4M4 12h4m12 0h.01M5 8h2a1 1 0 001-1V5a1 1 0 00-1-1H5a1 1 0 00-1 1v2a1 1 0 001 1zm12 0h2a1 1 0 001-1V5a1 1 0 00-1-1h-2a1 1 0 00-1 1v2a1 1 0 001 1zM5 20h2a1 1 0 001-1v-2a1 1 0 00-1-1H5a1 1 0 00-1 1v2a1 1 0 001 1z" />
            </svg>
            Vào Cổng Điểm Danh
          </Link>
          <a
            href="http://localhost:3000/api/health"
            target="_blank"
            rel="noopener noreferrer"
            className="w-full sm:w-auto py-3.5 px-5 rounded-xl bg-white hover:bg-slate-50 text-slate-700 font-semibold text-sm border border-slate-300 shadow-xs hover:border-slate-400 transition-all duration-200 flex items-center justify-center gap-2"
          >
            Kiểm tra API
          </a>
        </div>

        {/* 3 Step Guide */}
        <div className="grid grid-cols-1 sm:grid-cols-3 gap-6 text-left w-full">
          <div className="bg-white p-6 rounded-2xl border border-slate-200 shadow-xs">
            <div className="w-9 h-9 rounded-lg bg-blue-100 text-blue-700 font-bold flex items-center justify-center text-sm mb-4">
              1
            </div>
            <h3 className="font-bold text-slate-900 text-sm mb-1">Quét mã QR trên lớp</h3>
            <p className="text-xs text-slate-500 leading-relaxed">
              Mở camera điện thoại quét mã QR đang hiển thị trên màn hình máy chiếu phòng học.
            </p>
          </div>

          <div className="bg-white p-6 rounded-2xl border border-slate-200 shadow-xs">
            <div className="w-9 h-9 rounded-lg bg-blue-100 text-blue-700 font-bold flex items-center justify-center text-sm mb-4">
              2
            </div>
            <h3 className="font-bold text-slate-900 text-sm mb-1">Nhập Email FPT</h3>
            <p className="text-xs text-slate-500 leading-relaxed">
              Nhập chính xác tài khoản email sinh viên (@fpt.edu.vn) có trong danh sách lớp.
            </p>
          </div>

          <div className="bg-white p-6 rounded-2xl border border-slate-200 shadow-xs">
            <div className="w-9 h-9 rounded-lg bg-blue-100 text-blue-700 font-bold flex items-center justify-center text-sm mb-4">
              3
            </div>
            <h3 className="font-bold text-slate-900 text-sm mb-1">Ghi nhận Có mặt</h3>
            <p className="text-xs text-slate-500 leading-relaxed">
              Hệ thống xác thực mã hợp lệ và đánh dấu Có mặt (P) ngay lập tức trên máy giảng viên.
            </p>
          </div>
        </div>
      </main>

      {/* Footer */}
      <footer className="w-full bg-white border-t border-slate-200 py-6 px-6 text-center text-xs text-slate-500">
        PRM393 Attendance System • Kết nối ứng dụng Desktop & Google Apps Script API
      </footer>
    </div>
  );
}

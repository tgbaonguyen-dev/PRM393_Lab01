# PRM393 Dynamic QR Attendance System

Hệ thống điểm danh sinh viên bằng mã QR động xoay vòng 15 giây dành cho Giảng viên (Flutter Desktop Windows) và Sinh viên (Next.js Web / Google Sheets Data Gateway).

---

## 1. Cấu trúc dự án

```text
PRM393_Lab01/
├── apps/
│   ├── desktop/            # Flutter Windows Desktop App (Giảng viên)
│   └── web/                # Next.js App Router (Student Web + 3-Layer API Backend)
├── apps-script/            # Google Apps Script Data Gateway (với LockService)
├── sample_data/            # Tệp mẫu FA26_Markbook.ods để kiểm thử
├── docs/                   # Tài liệu SRS v4.0 & Kiến trúc hệ thống
└── ai/                     # Context & quy ước nghiệp vụ
```

---

## 2. Hướng dẫn chạy thử nghiệm cục bộ (Local Development)

### A. Khởi chạy Web & Backend API
```bash
cd apps/web
npm run dev
```
- Trang điểm danh sinh viên: `http://localhost:3000/checkin`
- Health check API: `http://localhost:3000/api/health`

### B. Khởi chạy Ứng dụng Desktop Giảng viên
```bash
cd apps/desktop
flutter run -d windows
```
- Ngay khi mở app, bạn có thể nhấn **"Mở FA26_Markbook.ods mẫu"** để nạp nhanh 8 bảng tính và kiểm tra toàn bộ quy trình: Nhập bảng điểm -> Xếp lịch học linh hoạt -> Mở ca chiếu mã QR xoay 15s -> Điểm danh trực tiếp -> Xuất báo cáo CSV.

---

## 3. Kết nối Google Sheets & Apps Script trên Cloud (Tùy chọn khi triển khai thật)

1. Tạo một trang tính **Google Sheets** mới trên Google Drive của bạn.
2. Chọn menu **Tiện ích mở rộng (Extensions)** > **Apps Script**.
3. Sao chép nội dung từ:
   - [`apps-script/Code.gs`](file:///d:/Github/Repositories/PRM393/PRM393_Lab01/apps-script/Code.gs)
   - [`apps-script/SheetRepository.gs`](file:///d:/Github/Repositories/PRM393/PRM393_Lab01/apps-script/SheetRepository.gs)
4. Nhấn **Triển khai (Deploy)** > **Tùy chọn triển khai mới (New deployment)**:
   - Loại: **Ứng dụng web (Web app)**
   - Thực thi dưới dạng: **Tôi (Me)**
   - Ai có quyền truy cập: **Bất kỳ ai (Anyone)**
5. Sao chép đường dẫn **URL ứng dụng web** nhận được và dán vào biến `APPS_SCRIPT_GATEWAY_URL` trong file `apps/web/.env.local`.

---

## 4. Tài liệu tham khảo
- [SRS v4.0](docs/SRS.md)
- [Target Architecture](docs/architecture.md)
- [Domain Glossary](ai/CONTEXT.md)

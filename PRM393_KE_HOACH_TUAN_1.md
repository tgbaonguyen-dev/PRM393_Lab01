# 📋 KẾ HOẠCH PHÂN CHIA NHIỆM VỤ THEO FEATURE (TUẦN 1)

## DỰ ÁN: PRM393 - HỆ THỐNG ĐIỂM DANH QR ĐỘNG (SRS v4.0)

> **Mục tiêu cốt lõi tuần 1:** Chạy thành công một lượt điểm danh mẫu xuyên suốt (End-to-End):
> Flutter Desktop (`/apps/desktop` mở phiên QR) -> Điện thoại quét QR -> Web Mobile Next.js (`/apps/web` Google Login GIS) -> Backend Dart Shelf (`/backend` 3 lớp) -> Google Apps Script (`/database` LockService) ghi Google Sheet -> Desktop Polling mỗi 5s hiển thị P.

---

## 1. Cấu trúc thư mục chuẩn theo mô hình Monorepo

- **Desktop App (Dart / Flutter):** Dành riêng cho Giảng viên trên Windows (`/apps/desktop`).
- **Web Client (Next.js / React):** Dành riêng cho Sinh viên quét QR trên điện thoại (`/apps/web`).
- **Backend API (Dart / Shelf):** Xây dựng theo kiến trúc 3 lớp (`Controller` -> `Service` -> `Repository`) phục vụ cả Desktop lẫn Web (`/backend`).

```text
PRM393_Lab01/
├── apps/
│   ├── desktop/                       # [GV] Ứng dụng Flutter Desktop trên Windows (Dart)
│   │   ├── lib/
│   │   │   ├── config.dart            # Cấu hình API_BASE_URL (kết nối Backend Dart)
│   │   │   ├── main.dart              # Entry point ứng dụng Desktop
│   │   │   └── features/
│   │   │       ├── import/            # (M1) Đọc file Markbook (.xlsx, .ods) & xem trước danh sách
│   │   │       ├── schedule/          # (M1) Màn hình sinh lịch 20 buổi học & điều chỉnh ngày
│   │   │       ├── session/           # (M2) Màn hình chiếu QR động đổi sau mỗi 15s đếm ngược
│   │   │       ├── attendance/        # (M4) Bảng theo dõi sĩ số realtime (polling 5s) & sửa A/P
│   │   │       └── export/            # (M5) Xuất báo cáo XLSX/CSV lưu trực tiếp về máy GV
│   │   └── pubspec.yaml
│   │
│   └── web/                           # [SV] Giao diện Web Mobile điểm danh (Next.js / TypeScript)
│       ├── app/
│       │   ├── checkin/               # (M3) Trang SV check-in khi quét QR
│       │   │   └── page.tsx           # Nhận params URL, Google Login (GIS) & 5 trạng thái phản hồi
│       │   ├── layout.tsx
│       │   └── page.tsx
│       ├── components/                # UI components (nút Google Sign-In, Card thông báo kết quả)
│       │   ├── GoogleSignInButton.tsx
│       │   └── StatusCard.tsx
│       ├── package.json
│       └── tsconfig.json
│
├── backend/                           # [API] Backend Dart Shelf theo chuẩn kiến trúc 3 lớp
│   ├── bin/
│   │   └── server.dart                # Server entry point (chạy port 8080)
│   ├── lib/
│   │   ├── controllers/               # [TẦNG 1: Controller] Tiếp nhận HTTP Requests & Trả JSON Response
│   │   │   ├── session_controller.dart    # (M2) GET /session/qr, POST /session/open, POST /session/close
│   │   │   ├── attendance_controller.dart # (M3, M4) POST /attendance/checkin, GET /session/:id/attendances, POST /attendance/manual-edit
│   │   │   └── schedule_controller.dart   # (M1) POST /schedule/save, GET /schedule/:classId
│   │   ├── services/                  # [TẦNG 2: Service] Logic nghiệp vụ & xử lý thuật toán
│   │   │   ├── qr_service.dart            # (M2) Sinh token HMAC-SHA256 bí mật & kiểm tra hạn 15s
│   │   │   ├── auth_service.dart          # (M3) Xác thực Google ID Token (lấy email chính chủ)
│   │   │   ├── session_service.dart       # (M2) Quản lý vòng đời phiên (open/close/reopen)
│   │   │   ├── attendance_service.dart    # (M4) Quy tắc chuyển A->P, chặn ghi đè sửa tay của GV
│   │   │   └── schedule_service.dart      # (M1) Logic sinh và kiểm tra lịch học
│   │   └── repositories/              # [TẦNG 3: Repository] Tầng giao tiếp dữ liệu bên ngoài
│   │       └── sheets_repository.dart     # (M5) Gửi HTTPS Request sang Google Apps Script Gateway
│   └── pubspec.yaml
│
├── database/                          # (M5) Script Google Apps Script & Seed data
│   ├── google_apps_script.js          # Web App LockService ghi tuần tự chống xung đột Sheet
│   └── seed_students.json             # Dữ liệu mẫu 5 tài khoản test
│
├── docs/                              # Tài liệu dự án
│   ├── SRS.md                         # Đặc tả yêu cầu phần mềm SRS v4.0
│   ├── architecture.md                # Kiến trúc hệ thống đích
│   └── ci.md                          # Hướng dẫn CI/CD
│
├── ai/                                # Ngữ cảnh cho AI Pair Programming
│   ├── CONTEXT.md                     # Thuật ngữ & quy ước nghiệp vụ
│   ├── DESIGN.md                      # Thiết kế kỹ thuật chi tiết
│   └── PROMPTS.md                     # Kịch bản prompt
│
└── test/                              # (M5) Kịch bản kiểm thử tích hợp End-to-End
    └── e2e_attendance_test.dart       # Script giả lập SV quét QR và check-in đồng thời
```

---

## 2. Luồng dữ liệu Tuần 1

```text
[GV: Flutter Desktop (/apps/desktop)]
       │ 1. Gọi GET /session/qr
       ▼
[Backend: Dart Shelf API (/backend)] ──(Sinh Token HMAC-SHA256 15s)──> [Hiển thị QR trên Desktop]
                                                                                │
                                                                                │ 2. SV quét camera điện thoại
                                                                                ▼
[SV: Next.js Web Mobile (/apps/web/app/checkin)] <──────────────────────────────┘
       │ 3. Đăng nhập Google Identity Services (GIS) -> Nhận Google ID Token (JWT)
       │ 4. Gửi POST /attendance/checkin { idToken, qrToken, sessionId, classId }
       ▼
[Backend: Dart Service Layer (/backend/lib/services)]
       │ 5. Verify QR Token (crypto HMAC-SHA256, < 15s) & Verify Google ID Token lấy email thật
       │ 6. Gửi payload CHECKIN qua HTTPS đến Google Apps Script
       ▼
[Google Apps Script (LockService)] ──(Ghi tuần tự an toàn)──> [Google Sheets Database]
       │                                                              │
       └──────── (Trả về JSON kết quả thành công) ────────────────────┘
                                                                      │
                                                                      │ 7. Polling mỗi 5s
                                                                      ▼
                                                    [GV: Flutter Desktop (/apps/desktop)]
                                                    (Cập nhật sĩ số và đổi màu P)
```

---

## 3. Phân chia chi tiết 5 Feature cho 5 Thành viên

---

### 👤 THÀNH VIÊN 1: Feature Nhập Markbook & Sinh Lịch 20 buổi

- **Mã Task SRS:** `IMP-01`, `IMP-02`, `IMP-03`, `IMP-04`, `IMP-05`, `IMP-06`, `FR-01` -> `FR-07`
- **Phạm vi file phụ trách:**
  - `apps/desktop/lib/features/import/import_screen.dart`
  - `apps/desktop/lib/features/schedule/schedule_generator_screen.dart`
  - `backend/lib/controllers/schedule_controller.dart`
  - `backend/lib/services/schedule_service.dart`
- **Nhiệm vụ cụ thể:**
  1. Viết bộ đọc file `.xlsx` và `.ods` trên Desktop Dart (dùng package `excel` / `spreadsheet_decoder`):
     - Đọc đúng 5 cột: `Class`, `RollNumber`, `FullName`, `Email`, `MemberCode`. Bỏ qua điểm, bonus, ExamDate.
     - Phân tích mã lịch từ tên sheet (ví dụ `12_PRM393` -> Thứ 2-5, slot 2: 09:30–11:45; `2X` -> Thứ 3-6; `3X` -> Thứ 4-7).
  2. Giao diện xem trước (Desktop): Hiển thị bảng danh sách SV, cảnh báo nếu thiếu cột hoặc trùng MSSV/Email.
  3. Giao diện sinh lịch (Desktop): GV chọn ngày bắt đầu -> tự động sinh 20 buổi học đúng thứ/slot; cho phép chỉnh sửa ngày từng buổi (nghỉ lễ, học bù).
  4. Backend Controller & Service: Nhận dữ liệu lớp/buổi học và xử lý lưu trữ.

---

### 👤 THÀNH VIÊN 2: Feature Quản lý Phiên & Trình chiếu QR Động

- **Mã Task SRS:** `DES-01`, `DES-02`, `API-04`, `API-05`, `FR-09`, `FR-10`, `FR-12`, `FR-13`
- **Phạm vi file phụ trách:**
  - `apps/desktop/lib/features/session/qr_display_screen.dart`
  - `backend/lib/controllers/session_controller.dart`
  - `backend/lib/services/qr_service.dart`
  - `backend/lib/services/session_service.dart`
- **Nhiệm vụ cụ thể:**
  1. Backend QR Service (Dart `crypto`):
     - Thuật toán tạo token ký bằng **HMAC-SHA256** với secret key bí mật ở server.
     - Hàm xác thực token: kiểm tra chữ ký hợp lệ và thời gian sống token không quá 15 giây.
  2. Backend Session Controller:
     - `POST /session/open`: Mở phiên, khởi tạo kết quả cả lớp là `A`.
     - `POST /session/close`: Đóng phiên, từ chối mọi lượt check-in sau đó.
     - `GET /session/qr`: Trả về URL check-in kèm token QR mới nhất.
  3. Giao diện Desktop (Flutter):
     - Màn hình hiển thị mã QR kích thước lớn (dùng `qr_flutter`).
     - Cài đặt `Timer.periodic(15s)` tự động gọi API lấy token mới và vẽ lại QR kèm thanh đếm ngược (15s -> 0s).

---

### 👤 THÀNH VIÊN 3: Feature Web Sinh viên Quét QR & Đăng nhập Google

- **Mã Task SRS:** `SET-02` (GIS), `API-06`, `API-07`, `FR-15`, `FR-16`, `FR-18`, `FR-20`, `FR-21`
- **Phạm vi file phụ trách:**
  - `apps/web/app/checkin/page.tsx`
  - `apps/web/components/GoogleSignInButton.tsx`
  - `backend/lib/controllers/attendance_controller.dart` (phần check-in)
  - `backend/lib/services/auth_service.dart`
- **Nhiệm vụ cụ thể:**
  1. Giao diện Web Mobile (Next.js / TailwindCSS):
     - Trang nhận tham số `token`, `classId`, `sessionId` từ URL khi SV quét QR.
     - Tích hợp Google Identity Services (nút "Sign in with Google") lấy Google ID Token (JWT).
  2. Backend Xác thực (Dart):
     - Dùng thư viện xác thực Google Token (hoặc gọi Google Token Info endpoint) để lấy email đã xác thực (tuyệt đối không nhận email gửi trực tiếp từ client).
     - Kiểm tra email có thuộc danh sách SV của lớp hay không.
  3. Giao diện 5 trạng thái phản hồi rõ ràng:
     - 🟢 Thành công (chuyển sang `P`).
     - 🟡 Đã điểm danh trước đó.
     - 🔴 QR hết hạn (yêu cầu quét mã mới nhất, giữ trạng thái đăng nhập Google).
     - 🔴 Không thuộc danh sách lớp học phần.
     - 🔴 Phiên điểm danh đã đóng.

---

### 👤 THÀNH VIÊN 4: Feature Polling Sĩ số Realtime & Sửa Điểm danh A/P

- **Mã Task SRS:** `DES-03`, `DES-04`, `DES-05`, `API-08`, `FR-11`, `FR-14`, `AC-10`
- **Phạm vi file phụ trách:**
  - `apps/desktop/lib/features/attendance/attendance_monitor_screen.dart`
  - `apps/desktop/lib/features/attendance/manual_edit_dialog.dart`
  - `backend/lib/controllers/attendance_controller.dart` (phần attendances & manual edit)
  - `backend/lib/services/attendance_service.dart`
- **Nhiệm vụ cụ thể:**
  1. Desktop Live Polling (Flutter):
     - Cài đặt `Timer.periodic(5s)` gọi `GET /session/:id/attendances` khi phiên đang mở.
     - Cập nhật thống kê sĩ số: `Có mặt: X / Tổng: Y`.
     - Bảng danh sách sinh viên: Tự động đổi màu dòng sinh viên từ Đỏ (`A`) sang Xanh lá (`P`) ngay khi lượt check-in được ghi nhận.
  2. Sửa thủ công (Manual Override):
     - Giao diện cho GV bấm trực tiếp để đổi trạng thái `A` <-> `P` cho bất kỳ sinh viên nào.
     - Gọi `POST /attendance/manual-edit` và đánh dấu `is_manual_edited = true` (ưu tiên cao nhất của GV; nếu GV đã sửa A thì SV quét lại không tự đổi thành P).

---

### 👤 THÀNH VIÊN 5: Feature Database Gateway, Xuất Báo Cáo XLSX & DevOps

- **Mã Task SRS:** `SET-02` (OAuth), `SET-04`, `DAT-01` -> `DAT-04`, `FR-22` -> `FR-25`, `QA-01`, `QA-03`
- **Phạm vi file phụ trách:**
  - `database/google_apps_script.js`
  - `database/seed_students.json`
  - `backend/lib/repositories/sheets_repository.dart`
  - `apps/desktop/lib/features/export/export_report_service.dart`
  - `test/e2e_attendance_test.dart`
  - `.github/workflows/ci.yml`
- **Nhiệm vụ cụ thể:**
  1. Google Sheets Database & Google Apps Script:
     - Tạo Sheet chuẩn 4 tab: `Classes`, `Students`, `Sessions`, `Attendances`.
     - Viết Apps Script với `LockService` xử lý ghi tuần tự chống xung đột khi nhiều SV check-in đồng thời -> Deploy lấy Web App URL.
     - Viết `sheets_repository.dart` trên Backend Dart để gửi request sang Apps Script URL.
  2. DevOps & Config:
     - Tạo OAuth 2.0 Web Client ID trên Google Cloud Console (cấp cho M3).
     - Cấu hình CI/CD GitHub Actions và hosting backend/web có HTTPS.
  3. Xuất Báo cáo (Desktop Flutter):
     - Viết module xuất file `.xlsx` và `.csv` kết quả các buổi học (giữ đúng Trống/A/P) lưu trực tiếp về máy GV.
  4. QA Lead:
     - Chuẩn bị bộ dữ liệu test 5 email thật và chủ trì buổi kiểm thử tích hợp End-to-End cuối tuần.

---

## 4. Thứ tự thực hiện (Tránh va chạm & Không ngồi chờ)

### ⏱️ Ngày 1: Khởi động & Chốt cổng giao tiếp (Contracts)

1. **Thành viên 5:** Lên Google Cloud Console tạo `GOOGLE_CLIENT_ID` giao cho M3; tạo Google Sheet mẫu và deploy Apps Script URL giao cho M2, M4.
2. **Cả nhóm thống nhất JSON Schema:**
   - Session Object: `{ sessionId, classId, date, slot, status }`
   - QR Object: `{ qrToken, expiresAt, qrUrl }`
   - Checkin Request: `{ idToken, qrToken, sessionId, classId }`
   - Attendance Record: `{ studentEmail, rollNumber, fullName, status, isManualEdited }`

### ⏱️ Ngày 2 đến Ngày 5: Code song song 100% trên các nhánh riêng

- Mỗi thành viên tạo nhánh Git riêng (`feat/import`, `feat/qr-session`, `feat/web-checkin`, `feat/monitor-edit`, `feat/db-export`).
- Chỉ làm việc trong các file thuộc phạm vi phân công.
- **Dùng Mock Data:** Nếu API phía đối tác chưa xong, dùng dữ liệu mẫu tĩnh để hoàn thiện giao diện và logic trước.

### ⏱️ Ngày 6 & 7: Ghép nối & Kiểm thử tích hợp (End-to-End)

- Ghép các module vào nhánh `develop`, chạy Backend Dart và Web Next.js.
- Cả 5 người cùng chạy kịch bản kiểm thử:
  1. GV mở app Desktop (Flutter) -> Mở phiên buổi 1.
  2. Màn hình hiện mã QR 15s đếm ngược.
  3. 5 thành viên dùng điện thoại quét mã -> Mở Web Next.js -> Đăng nhập Google.
  4. Điện thoại báo thành công.
  5. Google Sheet cập nhật chữ `P`.
  6. Desktop polling nhảy sĩ số `5/5` và chuyển danh sách sang màu xanh lá.
  7. Test mã quá 15s -> Báo lỗi hết hạn chính xác.

---

## 5. Tiêu chí nghiệm thu hoàn thành Tuần 1 (Definition of Done)

- [ ] Đọc được file danh sách `.xlsx`/`.ods` và sinh được lịch 20 buổi trên Flutter Desktop (`apps/desktop`).
- [ ] Desktop mở phiên, hiển thị QR đổi mới mỗi 15 giây kèm bộ đếm ngược.
- [ ] Web Next.js (`apps/web`) trên điện thoại nhận token, đăng nhập Google Identity Services và xác thực server-side thành công.
- [ ] Backend Dart (`backend`) xử lý đúng 3 lớp: Controller -> Service -> Repository.
- [ ] Google Sheets ghi nhận đúng `P` và không bị mất dữ liệu khi quét đồng thời (LockService).
- [ ] Desktop tự động cập nhật sĩ số mỗi 5 giây và cho phép GV sửa tay `A`/`P`.
- [ ] Xuất được file báo cáo `.xlsx`/`.csv` về máy tính.

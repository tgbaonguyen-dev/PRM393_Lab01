# PRM393 Dart Shelf Backend API (Port 8080)

Backend API phục vụ hệ thống điểm danh QR xoay vòng PRM393, được xây dựng bằng Dart Shelf theo kiến trúc 3 lớp:

## Kiến trúc 3 Lớp (Three-Layer Architecture)

- **Controllers** (`lib/controllers/`): Tiếp nhận request HTTP, validate tham số, gọi Service và trả về JSON Response.
  - `AttendanceController`: `/api/attendance/checkin`, `/api/attendance/override`, `/api/attendance/poll`, `/api/attendance/window`
  - `ClassController`: `/api/class/sync`
  - `QrController`: `/api/qr/generate`
- **Services** (`lib/services/`): Xử lý quy tắc nghiệp vụ.
  - `AttendanceService`: Kiểm tra quyền điểm danh, tính hợp lệ ca mở, xử lý override.
  - `QrService`: Tạo và xác thực mã HMAC-SHA256 xoay vòng 15 giây.
- **Repositories** (`lib/repositories/`): Tương tác với tầng dữ liệu bên ngoài.
  - `DataGatewayRepository`: Gọi sang Google Apps Script Data Gateway với cơ chế xử lý HTTP 302 Redirect của Google.

## Khởi chạy

```bash
dart run bin/server.dart
```

Mặc định lắng nghe tại: `http://localhost:8080` (hoặc `http://0.0.0.0:8080`).

# 🎓 PRM393 - Hệ Thống Điểm Danh Sinh Viên Bằng Mã QR Động & Google Sheets Realtime

Hệ thống điểm danh sinh viên chuyên nghiệp dành cho môn học **PRM393** (và các môn FAP), kết hợp giữa **Ứng dụng Giảng viên trên Desktop (Flutter)**, **Web Điểm danh Sinh viên (Next.js)**, **Backend API 3 lớp (Dart Shelf)** và **Cơ sở dữ liệu đám mây Google Sheets (Google Apps Script Gateway)**.

---

## 📑 Mục Lục
1. [Kiến Trúc Tổng Quan](#1-kiến-trúc-tổng-quan)
2. [Cấu Trúc Thư Mục Dự Án](#2-cấu-trúc-thư-mục-dự-án)
3. [Khởi Chạy Nhanh 1-Click (Quick Start)](#3-khởi-chạy-nhanh-1-click-quick-start)
4. [Cấu Hình Google Sheets & Apps Script](#4-cấu-hình-google-sheets--apps-script)
5. [Hướng Dẫn Sử Dụng Chi Tiết](#5-hướng-dẫn-sử-dụng-chi-tiết)
   - [5.1. Nhập Bảng Điểm (.ods / .xlsx)](#51-nhập-bảng-điểm-ods--xlsx)
   - [5.2. Quản Lý Lịch Giảng Dạy FAP](#52-quản-lý-lịch-giảng-dạy-fap)
   - [5.3. Đồng Bộ Đám Mây Google Sheets](#53-đồng-bộ-đám-mây-google-sheets)
   - [5.4. Chiếu Mã QR Động 15 Giây](#54-chiếu-mã-qr-động-15-giây)
   - [5.5. Sinh Viên Quét Mã Điểm Danh Trên Web](#55-sinh-viên-quét-mã-điểm-danh-trên-web)
   - [5.6. Chỉnh Sửa Điểm Danh Thủ Công (Realtime Drive)](#56-chỉnh-sửa-điểm-danh-thủ-công-realtime-drive)
   - [5.7. Xuất Báo Cáo](#57-xuất-báo-cáo)
6. [Xử Lý Sự Cố Thường Gặp (Troubleshooting)](#6-xử-lý-sự-cố-thường-gặp-troubleshooting)

---

## 1. Kiến Trúc Tổng Quan

Hệ thống tuân thủ mô hình phân lớp rõ ràng, bảo mật và khả năng mở rộng:

```text
[ Desktop App (Flutter Windows) ]       [ Student Web (Next.js) ]
       (Dành cho Giảng viên)              (Sinh viên quét QR)
                │                                  │
                └───► [ Dart Shelf Backend API ] ◄──┘
                          (Port 8080: 3-Layer)
                                  │
                                  ▼
                [ Google Apps Script Web App Gateway ]
                         (LockService chống đua)
                                  │
                                  ▼
                [ Google Sheets (Database trên Drive) ]
```

* **Desktop Giảng viên (`apps/desktop`)**: Viết bằng Flutter Desktop (Windows), hỗ trợ import markbook đa lớp, quản lý thời khoá biểu, chiếu mã QR động, theo dõi sĩ số trực tiếp.
* **Student Web UI (`apps/web`)**: Viết bằng Next.js (Port 3000), giao diện hiện đại tối ưu cho điện thoại và máy tính để sinh viên quét mã và xác nhận điểm danh.
* **Backend API (`backend/`)**: Viết bằng Dart Shelf chạy tại port 8080 theo chuẩn kiến trúc 3 lớp (**Controller - Service - Repository**), quản lý mã QR HMAC-SHA256 bảo mật xoay vòng 15 giây.
* **Data Gateway (`apps-script/`)**: Google Apps Script triển khai dưới dạng Web App, sử dụng `LockService` tuần tự hóa các lượt điểm danh đồng thời, ghi trực tiếp vào từng ô Slot của sinh viên trên Google Drive.

---

## 2. Cấu Trúc Thư Mục Dự Án

```text
PRM393_Lab01/
├── apps/
│   ├── desktop/            # Flutter Windows Desktop App (Giảng viên)
│   │   ├── lib/
│   │   │   ├── core/network/api_client.dart   # Kết nối Backend Port 8080
│   │   │   └── main.dart                      # UI chính: Import, Lịch, QR Live
│   │   └── attendance_database.json           # Bộ nhớ cục bộ offline
│   └── web/                # Next.js App Router (Sinh viên)
│       ├── src/app/checkin/ # Trang web điểm danh sinh viên
│       └── .env.local       # Cấu hình môi trường Web
├── backend/                # Dart Shelf Backend Server (Port 8080)
│   ├── bin/server.dart     # Entry point khởi chạy server
│   └── lib/
│       ├── controllers/    # Tầng Controller (HTTP Routing, Validation)
│       ├── services/       # Tầng Service (HMAC QR Token, Logic điểm danh)
│       ├── repositories/   # Tầng Repository (Kết nối Google Apps Script)
│       └── config.dart     # Cấu hình Port, Secret key, Apps Script URL
├── apps-script/            # Google Apps Script Gateway
│   ├── Code.gs             # Xử lý doPost, doGet và LockService
│   └── SheetRepository.gs  # Tạo Overview, Sheet lớp, ghi điểm danh Realtime
├── sample_data/
│   └── FA26_Markbook.ods   # File điểm danh mẫu 8 lớp học FAP
├── run.ps1                 # Script 1-click chạy cả 3 ứng dụng (PowerShell)
├── run.bat                 # Script 1-click chạy cả 3 ứng dụng (Command Prompt)
├── stop_dev.bat            # Script 1-click giải phóng Port 8080 & 3000
├── docs/                   # Tài liệu kiến trúc & SRS
└── README.md               # Tài liệu hướng dẫn sử dụng
```

---

## 3. Khởi Chạy Nhanh 1-Click (Quick Start)

Hệ thống cung cấp sẵn các file khởi chạy tự động cả 3 ứng dụng cùng lúc.

### Cách 1: Chạy bằng PowerShell (Khuyên dùng)
Mở cửa sổ PowerShell tại thư mục gốc của dự án và chạy:
```powershell
.\run.ps1
```

### Cách 2: Nhấp đúp chuột trên Windows
- Nhấp đúp vào file **`run.bat`** ở thư mục gốc của dự án.

Lập tức 3 cửa sổ console sẽ được mở độc lập:
1. `PRM393 Backend (8080)`: Server API Dart Shelf.
2. `PRM393 Student Web (3000)`: Web Next.js cho sinh viên.
3. `PRM393 Flutter Desktop`: Cửa sổ ứng dụng Desktop Windows cho Giảng viên.

### Cách dừng toàn bộ hệ thống:
Khi muốn đóng hoàn toàn hoặc giải phóng cổng 8080 & 3000, nhấp đúp vào:
```powershell
.\stop_dev.bat
```

---

## 4. Cấu Hình Google Sheets & Apps Script

Nếu bạn muốn kết nối với file Google Sheets trên Google Drive cá nhân:

### Bước 1: Tạo Google Sheet & Mở Apps Script
1. Mở [Google Sheets](https://sheets.new) và tạo một bảng tính trống mới.
2. Trên thanh menu, chọn **Tiện ích mở rộng (Extensions)** ➔ **Apps Script**.

### Bước 2: Dán Code vào Apps Script
Trong trình soạn thảo Google Apps Script:
1. Mở file **`Code.gs`**: Xoá hết nội dung cũ, copy toàn bộ nội dung file [apps-script/Code.gs](file:///d:/Github/Repositories/PRM393/PRM393_Lab01/apps-script/Code.gs) và dán vào.
2. Nhấn dấu **+** bên cạnh mục *Tệp* ➔ Chọn **Script** ➔ Đặt tên là `SheetRepository`.
3. Copy toàn bộ nội dung file [apps-script/SheetRepository.gs](file:///d:/Github/Repositories/PRM393/PRM393_Lab01/apps-script/SheetRepository.gs) và dán vào.
4. Bấm biểu tượng đĩa mềm **💾 Lưu (Ctrl + S)**.

### Bước 3: Triển Khai (Deploy) Thành Web App
1. Ở góc trên cùng bên phải, nhấn nút xanh **Triển khai (Deploy)** ➔ **Tùy chọn triển khai mới (New deployment)**.
2. Nhấn vào biểu tượng bánh răng ⚙️ ➔ Chọn **Ứng dụng web (Web app)**.
3. Điền thông tin cấu hình:
   - **Mô tả (Description)**: `PRM393 Data Gateway`
   - **Thực thi dưới dạng (Execute as)**: `Tôi (Me / email của bạn)`
   - **Ai có quyền truy cập (Who has access)**: **`Bất kỳ ai (Anyone)`** *(Bắt buộc để sinh viên quét QR không bị chặn đăng nhập)*
4. Nhấn **Triển khai (Deploy)**. Nếu Google yêu cầu quyền, hãy chọn *Ủy quyền truy cập* ➔ Chọn tài khoản của bạn ➔ *Advanced (Nâng cao)* ➔ *Go to PRM393 (unsafe)* ➔ *Allow*.
5. **Sao chép URL ứng dụng web** (có dạng `https://script.google.com/macros/s/.../exec`).

### Bước 4: Cập nhật URL vào Dự Án
Dán URL bạn vừa copy vào 2 vị trí:
1. Trong file [backend/lib/config.dart](file:///d:/Github/Repositories/PRM393/PRM393_Lab01/backend/lib/config.dart):
   ```dart
   static final String appsScriptGatewayUrl = Platform.environment['APPS_SCRIPT_GATEWAY_URL'] ??
       'https://script.google.com/macros/s/YOUR_DEPLOYMENT_ID/exec';
   ```
2. Trong file [apps/web/.env.local](file:///d:/Github/Repositories/PRM393/PRM393_Lab01/apps/web/.env.local):
   ```env
   APPS_SCRIPT_GATEWAY_URL=https://script.google.com/macros/s/YOUR_DEPLOYMENT_ID/exec
   ```

> ⚠️ **LƯU Ý KHI SỬA CODE APPS SCRIPT**: Mỗi lần chỉnh sửa code trong trình soạn thảo Apps Script, bạn **bắt buộc** phải bấm **Triển khai** ➔ **Quản lý các bản triển khai (Manage deployments)** ➔ Biểu tượng **cây bút ✏️** ➔ Phiên bản chọn **"Phiên bản mới" (New version)** ➔ **Triển khai** thì URL mới nhận được code mới.

---

## 5. Hướng Dẫn Sử Dụng Chi Tiết

Quy trình sử dụng trọn vẹn dành cho Giảng viên:

### 5.1. Nhập Bảng Điểm (.ods / .xlsx)
1. Mở ứng dụng Desktop Flutter.
2. Tại màn hình **Nhập Bảng điểm (Import Markbook)**:
   - Nhấn **"Chọn tệp từ máy tính"** để tải lên file điểm danh kỳ học (`.ods` hoặc `.xlsx`).
   - Hoặc nhấn nhanh nút **"Mở FA26_Markbook.ods mẫu"** để nạp ngay 8 lớp học FAP có sẵn trong thư mục `sample_data/`.
3. Hệ thống sẽ tự động bóc tách:
   - Tên môn, mã lớp (ví dụ: `PRM393 - SE1917`, `PRN232 - SE1920`).
   - Mã lịch học FAP (`12`, `14`, `21`, `22`, `23`, `24`, `31`, `32`).
   - Tổng số slot học (20 hoặc 30 buổi).
   - Danh sách sinh viên (STT, MSSV, Họ và tên, Email FPT, Mã FAP).

---

### 5.2. Quản Lý Lịch Giảng Dạy FAP
1. Chuyển sang tab **Lịch Giảng dạy (Schedule)** ở thanh điều hướng bên trái.
2. Chọn **Ngày bắt đầu học kỳ** (Ví dụ: `07/09/2026`).
3. Hệ thống tự động tính toán chính xác ngày học cho từng Slot theo quy tắc FAP:
   - **Mã 12 / 14**: Học Thứ 2 & Thứ 5.
   - **Mã 21 / 22 / 23 / 24**: Học Thứ 3 & Thứ 6.
   - **Mã 31 / 32**: Học Thứ 4 & Thứ 7.
4. Giảng viên có thể chọn từng lớp trong danh sách dropdown để kiểm tra danh sách 20 slot học cụ thể.

---

### 5.3. Đồng Bộ Đám Mây Google Sheets
1. Ở góc trên bên phải, bấm nút **"Đồng bộ Google Sheet"** (hoặc nút mây xanh).
2. Hệ thống sẽ kết nối với Google Apps Script và tự động khởi tạo:
   - **Tab `Overview`**: Bảng tổng quan 8 lớp học, số lượng sinh viên, lịch học và ngày khai giảng.
   - **8 Tab chi tiết từng lớp** (`12_PRM393_SE1917`, `11_PRN232_SE1917`...): Bao gồm toàn bộ danh sách sinh viên, các cột Slot từ 1 đến 20, cùng **công thức tính tự động tỉ lệ vắng và cảnh báo CẤM THI (>20%)**.
3. Bạn có thể bấm nút **"Google Sheet ➔ Mở trên Drive ↗"** ở góc dưới thanh sidebar để mở trực tiếp trang tính trên trình duyệt.

---

### 5.4. Chiếu Mã QR Động 15 Giây
1. Chuyển sang tab **Điểm danh Live** ở sidebar.
2. Chọn lớp học và buổi học hiện tại (ví dụ: *Buổi 01*).
3. Nhấn nút xanh **"Bắt đầu Mở Ca Điểm Danh"**:
   - Trạng thái ca chuyển sang **ĐANG PHÁT**.
   - Mã QR sẽ xuất hiện trên khung máy chiếu với thanh đếm ngược **15 giây**.
   - Mỗi 15 giây, một mã QR HMAC-SHA256 mới được Backend tạo ra để chống gian lận (sinh viên chụp ảnh gửi cho bạn ở nhà sẽ không kịp điểm danh).
4. Giảng viên chỉ cần phóng to màn hình máy chiếu cho cả lớp nhìn thấy mã QR.

---

### 5.5. Sinh Viên Quét Mã Điểm Danh Trên Web
1. Sinh viên dùng điện thoại hoặc laptop quét mã QR được chiếu trên bảng (Mã QR chứa đường dẫn đến trang web: `http://localhost:3000/checkin?token=...` hoặc IP mạng nội bộ).
2. Sinh viên nhập **Email trường (@fpt.edu.vn)** và bấm **Xác nhận Điểm Danh**.
3. Hệ thống kiểm tra:
   - Mã QR có còn hiệu lực trong vòng 15 giây không.
   - Ca điểm danh có đang mở không.
   - Email sinh viên có thuộc danh sách lớp học này không.
4. Nếu hợp lệ:
   - Trang web thông báo **"Điểm danh thành công!"**.
   - Cột sĩ số trên màn hình Desktop của Giảng viên tự động tăng lên.
   - Ô tương ứng của sinh viên trên Google Drive lập tức chuyển sang **màu xanh lá (P - Có mặt)**.

---

### 5.6. Chỉnh Sửa Điểm Danh Thủ Công (Realtime Drive)
Giảng viên toàn quyền điều chỉnh trạng thái điểm danh của từng sinh viên:
1. Trên màn hình Desktop (Danh sách sinh viên bên phải mã QR):
2. Nhấp trực tiếp vào tên sinh viên hoặc nút trạng thái để chuyển đổi:
   - **Có mặt (P)** (Nền xanh lá)
   - **Vắng mặt (A)** (Nền đỏ)
3. **Cập nhật Realtime tức thì**: Khi bấm đổi trạng thái, ứng dụng gửi lệnh ngay tới Google Drive. Ô Slot của sinh viên đó trên Google Sheets sẽ **đổi chữ và màu sắc ngay tức khắc trong 1 giây mà không cần bấm lưu hay tải lại trang!**

---

### 5.7. Xuất Báo Cáo
1. Chuyển sang tab **Xuất Báo cáo (Export)**.
2. Chọn lớp học muốn xuất kết quả.
3. Chọn định dạng xuất:
   - **Xuất CSV FAP Format**: Định dạng chuẩn để nộp hoặc nhập lên cổng FAP trường.
   - **Xuất Excel (.xlsx)**: Bảng điểm đầy đủ có định dạng màu và thống kê tỉ lệ chuyên cần.

---

## 6. Xử Lý Sự Cố Thường Gặp (Troubleshooting)

### Q1: Bị lỗi `SocketException: Only one usage of each socket address (port 8080)`?
* **Nguyên nhân**: Cổng 8080 đang bị một tiến trình Backend cũ chiếm giữ.
* **Cách xử lý**: Nhấp đúp vào file **`stop_dev.bat`** để giải phóng toàn bộ cổng 8080 và 3000, sau đó chạy lại `.\run.ps1`.

---

### Q2: Trên Google Drive chỉ có 1 tab tên là `Temp_...` mà không thấy danh sách lớp?
* **Nguyên nhân**: Google Apps Script đang chạy phiên bản cũ chưa có hàm `syncAllClasses`.
* **Cách xử lý**:
  1. Mở dự án Google Apps Script.
  2. Bấm **Triển khai** ➔ **Quản lý các bản triển khai**.
  3. Bấm **cây bút ✏️** ➔ Phiên bản chọn **"Phiên bản mới" (New version)** ➔ Bấm **Triển khai**.
  4. Quay lại app Desktop bấm nút **"Đồng bộ Google Sheet"**.

---

### Q3: Bấm đổi trạng thái sinh viên trên Desktop nhưng Google Sheet không đổi màu?
1. Đảm bảo cửa sổ terminal **PRM393 Backend (8080)** đang chạy.
2. Kiểm tra xem file [backend/lib/config.dart](file:///d:/Github/Repositories/PRM393/PRM393_Lab01/backend/lib/config.dart) đã điền đúng URL Web App Apps Script mới nhất chưa.
3. Khi bạn bấm đổi trạng thái, hãy nhìn vào terminal Backend: Nó sẽ in ra dòng:
   `[DataGateway] saveManualOverride (...) -> SUCCESS` chứng minh ô đã được ghi thành công lên Drive!

---

## 7. Liên Hệ & Đóng Góp
- **Môn học**: PRM393 - Mobile Programming (FPT University)
- **Kiến trúc**: Flutter Desktop Windows + Next.js App Router + Dart Shelf 3-Layer + Google Apps Script Web App Gateway.

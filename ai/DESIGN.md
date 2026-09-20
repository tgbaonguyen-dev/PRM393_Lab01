# DESIGN.md — Notion Workspace / Academic Minimalist System

Hệ thống thiết kế chuẩn Notion Workspace dành riêng cho ứng dụng Desktop quản trị giảng dạy, lịch biểu và điểm danh trực tiếp (**EduCheck Pro**). Được tối ưu hoá nhằm loại bỏ cảm giác "AI-generated", hướng tới trải nghiệm tài liệu số thủ công, tối giản, thanh nhã và tập trung tuyệt đối vào nội dung học vụ.

---

## 1. Nguyên Tắc Thiết Kế Cốt Lõi (Core Principles)

1. **Crafted Document Over Web App (Văn bản số thay vì Web App truyền thống):**
   - Loại bỏ các khối hộp đổ bóng dày (drop shadow), gradient sặc sỡ và container bo góc cồng kềnh.
   - Giao diện sử dụng cấu trúc phẳng (flat), ngăn cách chủ yếu bằng đường phân cách siêu mảnh 1px hoặc khoảng trắng tự nhiên (whitespace rhythm).

2. **Subtle & Warm Contrast (Tương phản ấm áp, không gắt mắt):**
   - Sử dụng sắc than chì (Charcoal `#37352F`) thay cho màu đen tuyền `#000000`.
   - Nền màu ngà ấm nhẹ (`#FAF9F6` / `#FFFFFF`) thay thế nền xám lạnh công nghiệp.

3. **No Decorative Icon In Text (Không lồng icon trang trí trong văn bản):**
   - Không đặt emoji hoặc icon nhỏ trước nhãn chữ (như `📅 Lịch`, `📱 Điểm danh`). Văn bản hiển thị thuần khiết (Text-only) để giữ vững tính học thuật và nghiêm túc.

4. **Consistent Title / Pascal Case (Đồng bộ viết hoa đầu từ):**
   - Tất cả các tiêu đề, nút bấm, nhãn trường, tab trạng thái và tiêu đề bảng đều áp dụng chuẩn Pascal Case / Title Case (Ví dụ: *Lịch Giảng Dạy Tuần*, *Điểm Danh Trực Tiếp*, *Đã Có Mặt*, *Tất Cả*).

5. **Notion Database Aesthetic (Chuẩn hiển thị Database của Notion):**
   - Bảng dữ liệu có header tối giản viết hoa nhẹ, dòng phân cách mỏng, nhãn phân loại (Select Tag) dạng màu pastel nhã nhặn.
   - Ô tìm kiếm thanh thoát, chiều cao cố định 32px, phím tắt `(⌘K)` tinh tế.

---

## 2. Bảng Màu Hệ Thống (Color Palette Tokens)

### 2.1. Nền & Cấu Trúc (Surfaces & Structural)
- **Base Canvas (Nền Trang):** `#FAF9F6` (Màu giấy trắng ngà đặc trưng Notion)
- **Container / Card Surface (Mặt Khối Thẻ):** `#FFFFFF`
- **Sidebar Surface (Thanh Bên):** `#F7F6F3`
- **Border / Divider (Đường Kẻ Phân Cách):** `#E3E2DE` (1px solid)
- **Subtle Row Hover (Hover Dòng/Mục):** `#F1F1EF`

### 2.2. Màu Chữ & Biểu Tượng (Typography & Iconography)
- **Text Primary (Nội Dung Chính, Tiêu Đề):** `#37352F` (Màu than chì tự nhiên)
- **Text Secondary (Nội Dung Phụ, Mã Học Phần):** `#787774` (Xám ấm)
- **Text Tertiary / Placeholder (Gợi Ý, Đường Dẫn Breadcrumb):** `#9B9A97`
- **Text Inverted (Chữ Trên Nền Đậm):** `#FFFFFF`

### 2.3. Màu Nhãn Trạng Thái Chuẩn Notion (Select Tags - Pastel System)
- **Green Tag (Đang Diễn Ra / Đã Có Mặt):**
  - Nền: `#EBF5F0`
  - Chữ: `#1F7A4D`
- **Yellow / Amber Tag (Sắp Tới / Có Phép / Nghỉ Phép):**
  - Nền: `#FDF5E6`
  - Chữ: `#B87214`
- **Blue Tag (Lý Thuyết / Thực Hành / Cần Chuẩn Bị):**
  - Nền: `#EFF6FF`
  - Chữ: `#1D4ED8`
- **Neutral Tag (Đã Xong / Tiết Bổ Trợ / Mã Phòng):**
  - Nền: `#F1F1EF`
  - Chữ: `#5A5955`

### 2.4. Hành Động & Điểm Nhấn (Interactive & CTA)
- **Button Primary (Hành Động Chính - e.g., Tạo Phiên / Kết Thúc):**
  - Nền: `#37352F`
  - Chữ: `#FFFFFF`
  - Hover: `#22201D`
- **Button Secondary / Outline (e.g., Hôm Nay, Xuất Báo Cáo):**
  - Nền: `#FFFFFF`
  - Viền: `1px solid #E3E2DE`
  - Chữ: `#37352F`
  - Hover: `#F7F6F3`

---

## 3. Hệ Thống Typography (Typographic Scale)

Hệ thống phông chữ ưu tiên các phông Sans-serif trung tính hoặc Serif phong cách tài liệu: `Inter`, `-apple-system`, `BlinkMacSystemFont`, `Newsreader`.

- **Page Title (Tiêu Đề Trang):**
  - Size: `24px` / `1.5rem` (`text-2xl` hoặc `font-headline-lg`)
  - Weight: `600` (Semi-bold)
  - Color: `#37352F`
  - Line Height: `1.2`
- **Section Heading / Class Name (Tên Môn Học, Tiêu Đề Mục):**
  - Size: `15px` – `16px`
  - Weight: `600`
  - Color: `#37352F`
- **Body / Content (Văn Bản Thông Thường):**
  - Size: `14px` (`text-sm`)
  - Weight: `400`
  - Color: `#37352F`
- **Metadata / Caption / Table Header (Số Liệu Phụ, Cột Bảng):**
  - Size: `12px` – `13px` (`text-xs`)
  - Weight: `500`
  - Color: `#787774`
  - Header: Thường đi kèm `uppercase tracking-wider` nhẹ.

---

## 4. Đặc Tả Thành Phần Giao Diện (Component Specifications)

### 4.1. Thanh Bên Điều Hướng (Sidebar Navigation)
- Chiều rộng: `240px` – `260px`, viền phải `1px solid #E3E2DE`.
- Mục danh mục: Chiều cao `32px`, góc bo `4px` (`rounded`), text padding `8px 12px`.
- Trạng thái Active: Nền `#EFEFED`, màu chữ `#37352F` đậm nét kèm chấm nhận diện siêu nhỏ (bullet indicator) bên phải nếu cần.
- Tuyệt đối không dùng emoji hoặc icon màu mè trước tên menu.

### 4.2. Thanh Công Cụ & Tìm Kiếm (Toolbar & Search Bar)
- **Kích thước chuẩn:** Chiều cao đúng `32px` (`h-8`), bán kính bo góc `4px` – `6px` (`rounded`).
- **Nền & Viền:** Nền `#FAF9F6` hoặc `#FFFFFF`, viền mảnh `1px solid #E3E2DE`.
- **Kính lúp:** Icon nét mảnh `14px` màu `#9B9A97`.
- **Placeholder & Phím tắt:** Text xám nhạt `13px`, hiển thị phím tắt `(⌘K)` tinh gọn.

### 4.3. Bảng Lịch Giảng Dạy Tuần (Weekly Schedule Matrix)
- Lưới 5 hoặc 6 cột (Thứ 2 đến Thứ 6/Thứ 7) với hàng phân ca học (Ca 1, Ca 2, Ca 3, Ca 4).
- Các ô trống **không điền text rườm rà** (không lặp lại cụm *"Không có tiết"*), giữ khoảng trắng thuần khiết.
- Thẻ môn học: Đặt vừa vặn trong ô lưới, nền trắng viền mỏng `1px solid #E3E2DE`, có mã môn (`CS201`), nhãn phân loại (`Lý Thuyết`, `Thực Hành`), phòng học và sĩ số.
- Ca học đang diễn ra có đường viền vi tế hoặc nhãn trạng thái nổi bật dạng Notion Tag.

### 4.4. Module Quét Mã QR & Điểm Danh (Live Attendance Section)
- **Khung QR Code:** Tương phản cao đen/trắng, kích thước tối ưu (từ `260px` đến `320px`), bao quanh bởi khung viền mỏng 1px, không đổ bóng.
- **Thanh tiến trình (Timer Progress):** Vạch ngang siêu mỏng màu than chì `#37352F` đếm ngược chu kỳ đổi mã (ví dụ `15s`).
- **Mã PIN Dự Phòng:** Khối số lớn rõ nét kèm nút làm mới nhỏ gọn cho sinh viên hỏng camera.

### 4.5. Bảng Danh Sách Sinh Viên (Notion Database Table View)
- Header bảng: Đường kẻ dưới mỏng 1px, tiêu đề cột: `#`, `Sinh Viên`, `MSSV`, `Thời Gian`, `Trạng Thái`.
- Phân loại bộ lọc: Cụm nút pill tối giản liền kề: `Tất Cả (65)`, `Đã Quét (52)`, `Chưa Quét (10)`, `Có Phép (3)`.
- Nhãn trạng thái sinh viên: Chuẩn Notion pill tag (`Đã Có Mặt` nền xanh pastel, `Nghỉ Phép` nền cam pastel, `Điểm Danh Bù` nền xám).

---

## 5. Quy Tắc Ứng Dụng (Implementation Rules)
1. Luôn sử dụng Tailwind tokens hoặc CSS variables dựa trên bảng màu `#FAF9F6`, `#37352F`, `#E3E2DE`.
2. Kiểm soát chặt chẽ quy chuẩn Pascal Case ở tất cả các label UI.
3. Không thêm các thư viện animation lượn sóng hoặc hiệu ứng chuyển động lòe loẹt; chỉ dùng transition màu sắc nhẹ nhàng (`150ms ease-in-out`).

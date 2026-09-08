# Ngữ cảnh dự án

## Hướng hiện tại

- Đồ án PRM393, nhóm 5 thành viên, thời gian dự kiến 3 tuần; môn học Flutter.
- Sản phẩm web điểm danh Dynamic QR, frontend Flutter Web và backend Dart, triển khai qua HTTPS.
- Phát triển theo Database First. Phân chia trách nhiệm backend xem `../docs/architecture.md`.
- MVP dự kiến triển khai cho một GV, dữ liệu chuẩn bị cho nhiều GV với lớp và lịch riêng.
- Giảng viên import Excel, mở QR, theo dõi/sửa kết quả và export. Sinh viên đăng nhập Google để check-in.
- Hướng dịch vụ đề xuất: Supabase cho database/Auth/Realtime; Render cho web/backend.

## Trạng thái yêu cầu

SRS là bản đề xuất của người khởi xướng, chưa được cả nhóm duyệt. Các quyết định trong task mới nhất của người dùng là nguồn cập nhật; không coi mọi ý trong SRS là đã chốt.

Những điểm cần xác minh trước khi làm phần liên quan:
- File Excel thực tế và ánh xạ cột.
- Phân biệt buổi học và số slot.
- Sửa danh sách nhập thiếu, import lại lịch và đổi email.
- Thứ tự ưu tiên sửa thủ công/check-in, lượt quét sát lúc đóng và điều kiện export.

Khi nhóm duyệt SRS, đặt bản được duyệt trong `docs/` và cập nhật đường dẫn tại đây. Không tự suy diễn nội dung còn thiếu thành requirement chính thức.

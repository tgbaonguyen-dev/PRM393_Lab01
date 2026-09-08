# Kiến trúc 3 lớp

- controllers: nhận HTTP request, gọi service, trả response.
- services (BLL): kiểm tra và xử lý nghiệp vụ.
- repositories (DAL): đọc/ghi database và thực hiện giao dịch.

Flutter trong frontend/lib gọi API backend. Controller không gọi database trực tiếp; service không chứa giao diện; repository không trả HTTP response.

DB First: thống nhất nghiệp vụ → thiết kế database/SQL → triển khai ba lớp. SRS còn cần nhóm review.

File Dart dùng snake_case, ví dụ attendance_controller.dart. Hiện chỉ có bộ khung thư mục, chưa có mã nguồn hoặc cấu hình chạy.

# Continuous Integration

Workflow `.github/workflows/ci.yml` chạy khi push, mở/cập nhật pull request và khi chạy thủ công qua GitHub Actions. Hai job độc lập: `frontend checks` và `backend checks`.

## Các kiểm tra

| Thành phần | Kiểm tra |
|---|---|
| Flutter frontend | Cài dependency, format, analyze, test nếu có, build web release |
| Dart backend | Cài dependency, format, analyze, test nếu có |

Lỗi format, analyze, test hoặc build làm job thất bại. Workflow chỉ kiểm tra và build, không deploy, không truy cập Supabase thật và không cần secret ở giai đoạn này.

## Khi repository còn là bộ khung

Chưa có pubspec.yaml và chưa có source Dart: job báo rõ chưa khởi tạo trong phần Summary, không cài SDK. Trạng thái xanh lúc này chỉ xác nhận bộ khung được nhận diện, không chứng minh ứng dụng đã chạy.

Có file Dart nhưng thiếu pubspec.yaml hoặc mất thư mục frontend/backend: CI thất bại. Khi đã khởi tạo package, các kiểm tra tự chạy. Khi nhóm hoàn tất khởi tạo cả hai package, đổi nhánh xử lý thiếu pubspec.yaml thành lỗi bắt buộc để tránh bỏ qua kiểm tra do xóa package.

Test chỉ chạy khi có file test/**/*_test.dart; thiếu test được báo trong Summary. Backend có test cần khai báo package test trong dev_dependencies. Kiểm tra tích hợp cần môi trường riêng sẽ được bổ sung theo yêu cầu sau.

## Dùng trong nhóm

1. Commit/push workflow lên GitHub hoặc đưa vào PR theo ruleset hiện có.
2. Mở tab Actions và xem kết quả CI. Workflow thủ công cần nằm trên nhánh mặc định.
3. Sau lần chạy đầu, chọn `frontend checks` và `backend checks` làm required status checks trong ruleset main.
4. Commit pubspec.lock của frontend và backend khi khởi tạo. CI tạm dùng SDK stable; nhóm cần chốt phiên bản SDK cụ thể trong workflow cùng phiên bản phát triển local khi khởi tạo.
5. Nếu web cần cấu hình build công khai như Supabase URL/publishable key, bổ sung cấu hình CI phù hợp lúc triển khai. Không đưa service-role key hoặc khóa ký QR vào Flutter.

Tham khảo: https://github.com/subosito/flutter-action, https://github.com/dart-lang/setup-dart và https://github.com/actions/checkout.

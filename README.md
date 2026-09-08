# PRM393 Lab01

## CI

GitHub Actions đã được cấu hình trong `.github/workflows/ci.yml` cho frontend và backend. Khi chưa có package Dart/Flutter, workflow báo chưa khởi tạo; khi có package, tự chạy format, analyze, test nếu có và build Flutter Web. Xem `docs/ci.md` để bật required checks trên GitHub.

Bộ khung Flutter Web và backend Dart theo kiến trúc 3 lớp, hướng Database First. Chưa có code hoặc dependency.

```text
frontend/lib/                  # Giao diện Flutter
backend/lib/controllers/       # Nhận request và trả response
backend/lib/services/          # BLL: xử lý nghiệp vụ
backend/lib/repositories/      # DAL: truy cập database
database/                      # SQL khi thiết kế database
docs/architecture.md           # Hướng dẫn ngắn
```

Luồng: Flutter → Controller → Service → Repository → Database.

Chỉ ba thư mục nghiệp vụ backend. File .gitkeep giữ thư mục trống trong Git. Khi triển khai mới thêm pubspec.yaml và các file cần thiết.

## Tài liệu dùng với AI

```text
AGENTS.md          # Hướng dẫn và đường dẫn tài liệu cho AI
ai/
├── CONTEXT.md     # Ngữ cảnh và các yêu cầu chưa chốt
├── DESIGN.md      # Quyết định giao diện
└── PROMPTS.md     # Mẫu giao task và review
```

Khi dùng AI, gửi task cụ thể và yêu cầu đọc AGENTS.md. Dùng tên AGENTS.md thay cho AGENT.md; các công cụ không tự nhận file này vẫn có thể đọc khi được chỉ định.

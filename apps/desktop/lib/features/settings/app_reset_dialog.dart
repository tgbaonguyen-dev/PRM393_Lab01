import 'package:flutter/material.dart';
import 'app_reset_service.dart';
import '../../shell/app_shell.dart';

class AppResetDialog extends StatefulWidget {
  final VoidCallback onReset;
  const AppResetDialog({super.key, required this.onReset});
  @override
  State<AppResetDialog> createState() => _AppResetDialogState();
}

class _AppResetDialogState extends State<AppResetDialog> {
  final _confirmation = TextEditingController();
  final _key = TextEditingController();
  final _service = AppResetService();
  bool _busy = false;
  bool _remoteDone = false;
  String? _error;

  @override
  void dispose() {
    _confirmation.dispose();
    _key.dispose();
    _service.dispose();
    super.dispose();
  }

  Future<void> _reset() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final nav = AppNavigationController.instance;
    nav.setResetting(true);
    // Dispose data views and stop their polling before starting the reset.
    await WidgetsBinding.instance.endOfFrame;
    try {
      if (!_remoteDone) {
        await _service.resetRemote(_key.text.trim());
        _remoteDone = true;
      }
      await _service.resetLocal();
      if (!mounted) return;
      widget.onReset();
      Navigator.pop(context);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      nav.setResetting(false);
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: AlertDialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      title: const Text('Xóa Toàn Bộ Dữ Liệu', style: TextStyle(fontSize: 20)),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Xóa lớp học, danh sách sinh viên, lịch, phiên và kết quả điểm danh trên máy, backend và Google Sheets, kể cả lịch sử. Thao tác không thể hoàn tác.\n\nFile Markbook gốc, file đã xuất và cấu hình kết nối được giữ nguyên.',
                style: TextStyle(fontSize: 13, height: 1.6),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _key,
                obscureText: true,
                enabled: !_busy,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(labelText: 'Khóa Quản Trị'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _confirmation,
                enabled: !_busy,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'Nhập XÓA TẤT CẢ để xác nhận',
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFFB42318),
                  ),
                ),
              ],
              if (_busy)
                const Padding(
                  padding: EdgeInsets.only(top: 16),
                  child: LinearProgressIndicator(),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Hủy'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFFB42318),
          ),
          onPressed:
              !_busy &&
                  _confirmation.text.trim() == 'XÓA TẤT CẢ' &&
                  _key.text.trim().isNotEmpty
              ? _reset
              : null,
          child: Text(
            _busy
                ? 'Đang Xóa…'
                : _remoteDone
                ? 'Thử Lại Xóa Cục Bộ'
                : 'Xóa Toàn Bộ',
          ),
        ),
      ],
    ),
  );
}

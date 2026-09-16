import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:qr_flutter/qr_flutter.dart';

import '../../config.dart';

enum _SessionViewState { idle, opening, open, closing, closed }

class QrDisplayScreen extends StatefulWidget {
  final String classId;
  final String sessionId;
  final String? className;
  final String? lessonLabel;
  final String apiBaseUrl;
  final http.Client? client;

  const QrDisplayScreen({
    super.key,
    required this.classId,
    required this.sessionId,
    this.className,
    this.lessonLabel,
    this.apiBaseUrl = AppConfig.apiBaseUrl,
    this.client,
  });

  @override
  State<QrDisplayScreen> createState() => _QrDisplayScreenState();
}

class _QrDisplayScreenState extends State<QrDisplayScreen> {
  late final http.Client _client;
  late final bool _ownsClient;
  Timer? _rotationTimer;
  Timer? _countdownTimer;
  _SessionViewState _viewState = _SessionViewState.idle;
  String? _windowId;
  String? _qrUrl;
  DateTime? _expiresAt;
  String? _errorMessage;
  int _secondsRemaining = 0;
  bool _isRefreshingQr = false;

  bool get _isOpen => _viewState == _SessionViewState.open;
  bool get _isBusy =>
      _viewState == _SessionViewState.opening ||
      _viewState == _SessionViewState.closing;

  @override
  void initState() {
    super.initState();
    _ownsClient = widget.client == null;
    _client = widget.client ?? http.Client();
  }

  @override
  void dispose() {
    _stopTimers();
    if (_ownsClient) _client.close();
    super.dispose();
  }

  Future<void> _openSession() async {
    setState(() {
      _viewState = _SessionViewState.opening;
      _errorMessage = null;
    });
    try {
      final response = await _client.post(
        _endpoint('/session/open'),
        headers: const {'content-type': 'application/json'},
        body: jsonEncode({
          'sessionId': widget.sessionId,
          'classId': widget.classId,
        }),
      );
      final data = _responseData(response);
      final windowId = data['windowId']?.toString().trim() ?? '';
      if (windowId.isEmpty) {
        throw const FormatException('Backend không trả về windowId.');
      }
      if (!mounted) return;
      setState(() {
        _windowId = windowId;
        _viewState = _SessionViewState.open;
      });
      _startTimers();
      await _fetchQr();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _viewState = _SessionViewState.idle;
        _errorMessage = _friendlyError(error);
      });
    }
  }

  Future<void> _fetchQr() async {
    if (!_isOpen || _isRefreshingQr) return;
    _isRefreshingQr = true;
    try {
      final uri = _endpoint('/session/qr').replace(
        queryParameters: {
          'sessionId': widget.sessionId,
          'classId': widget.classId,
        },
      );
      final response = await _client.get(uri);
      final data = _responseData(response);
      final qrUrl = data['qrUrl']?.toString().trim() ?? '';
      final expiresAtMs = int.tryParse(data['expiresAt']?.toString() ?? '');
      if (qrUrl.isEmpty || expiresAtMs == null) {
        throw const FormatException('Dữ liệu QR từ backend không hợp lệ.');
      }
      final expiresAt = DateTime.fromMillisecondsSinceEpoch(
        expiresAtMs,
        isUtc: true,
      );
      if (!mounted || !_isOpen) return;
      setState(() {
        _qrUrl = qrUrl;
        _expiresAt = expiresAt;
        _secondsRemaining = _remainingSeconds(expiresAt);
        _errorMessage = null;
      });
    } catch (error) {
      if (!mounted || !_isOpen) return;
      setState(() {
        _qrUrl = null;
        _expiresAt = null;
        _secondsRemaining = 0;
        _errorMessage = _friendlyError(error);
      });
    } finally {
      _isRefreshingQr = false;
    }
  }

  Future<void> _closeSession() async {
    final windowId = _windowId;
    if (!_isOpen || windowId == null) return;
    setState(() {
      _viewState = _SessionViewState.closing;
      _errorMessage = null;
    });
    try {
      final response = await _client.post(
        _endpoint('/session/close'),
        headers: const {'content-type': 'application/json'},
        body: jsonEncode({
          'sessionId': widget.sessionId,
          'classId': widget.classId,
          'windowId': windowId,
        }),
      );
      _responseData(response);
      if (!mounted) return;
      _stopTimers();
      setState(() {
        _viewState = _SessionViewState.closed;
        _qrUrl = null;
        _expiresAt = null;
        _secondsRemaining = 0;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _viewState = _SessionViewState.open;
        _errorMessage = _friendlyError(error);
      });
    }
  }

  void _startTimers() {
    _stopTimers();
    _rotationTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) => unawaited(_fetchQr()),
    );
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final expiresAt = _expiresAt;
      if (!mounted || !_isOpen || expiresAt == null) return;
      final remaining = _remainingSeconds(expiresAt);
      if (remaining != _secondsRemaining) {
        setState(() => _secondsRemaining = remaining);
      }
    });
  }

  void _stopTimers() {
    _rotationTimer?.cancel();
    _countdownTimer?.cancel();
    _rotationTimer = null;
    _countdownTimer = null;
  }

  int _remainingSeconds(DateTime expiresAt) {
    final milliseconds =
        expiresAt.difference(DateTime.now().toUtc()).inMilliseconds;
    if (milliseconds <= 0) return 0;
    return (milliseconds / 1000).ceil().clamp(0, 15).toInt();
  }

  Uri _endpoint(String path) {
    final base = Uri.parse(widget.apiBaseUrl);
    final normalizedBasePath =
        base.path.endsWith('/')
            ? base.path.substring(0, base.path.length - 1)
            : base.path;
    return base.replace(path: '$normalizedBasePath$path');
  }

  Map<String, dynamic> _responseData(http.Response response) {
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Phản hồi backend không hợp lệ.');
    }
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        decoded['success'] != true) {
      throw _ApiException(
        decoded['message']?.toString() ??
            decoded['error']?.toString() ??
            'Backend trả về HTTP ${response.statusCode}.',
      );
    }
    final data = decoded['data'];
    if (data is! Map<String, dynamic>) {
      throw const FormatException('Backend không trả về dữ liệu phiên.');
    }
    return data;
  }

  String _friendlyError(Object error) {
    if (error is _ApiException) return error.message;
    if (error is FormatException) return error.message;
    return 'Không thể kết nối backend. Vui lòng kiểm tra API và thử lại.';
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Trình chiếu QR điểm danh'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 20),
            child: Center(child: _StatusBadge(state: _viewState)),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 920),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _SessionHeader(
                    className: widget.className ?? widget.classId,
                    lessonLabel: widget.lessonLabel ?? widget.sessionId,
                  ),
                  const SizedBox(height: 20),
                  Card(
                    elevation: 0,
                    child: Padding(
                      padding: const EdgeInsets.all(28),
                      child: Column(
                        children: [
                          LayoutBuilder(
                            builder: (context, constraints) {
                              final qrSize = math.min(
                                constraints.maxWidth,
                                420.0,
                              );
                              return SizedBox(
                                width: qrSize,
                                height: qrSize,
                                child: _QrPanel(
                                  qrUrl: _qrUrl,
                                  state: _viewState,
                                  onRetry: _isOpen ? _fetchQr : null,
                                ),
                              );
                            },
                          ),
                          const SizedBox(height: 24),
                          if (_isOpen) ...[
                            Text(
                              'Mã mới sau $_secondsRemaining giây',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 10),
                            LinearProgressIndicator(
                              value: _secondsRemaining / 15,
                              minHeight: 8,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Sinh viên quét mã bằng camera điện thoại để mở trang điểm danh.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ] else
                            Text(
                              _viewState == _SessionViewState.closed
                                  ? 'Phiên đã đóng. Kết quả hiện tại được giữ nguyên.'
                                  : 'Mở phiên để khởi tạo điểm A và bắt đầu trình chiếu QR.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  if (_errorMessage != null) ...[
                    const SizedBox(height: 16),
                    MaterialBanner(
                      content: Text(_errorMessage!),
                      leading: Icon(
                        Icons.error_outline,
                        color: colorScheme.error,
                      ),
                      backgroundColor: colorScheme.errorContainer,
                      actions: [
                        TextButton(
                          onPressed: () => setState(() => _errorMessage = null),
                          child: const Text('Đóng'),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (!_isOpen && _viewState != _SessionViewState.closing)
                        FilledButton.icon(
                          onPressed: _isBusy ? null : _openSession,
                          icon:
                              _viewState == _SessionViewState.opening
                                  ? const SizedBox.square(
                                    dimension: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                  : const Icon(Icons.play_arrow),
                          label: Text(
                            _viewState == _SessionViewState.closed
                                ? 'Mở lại phiên'
                                : 'Mở phiên điểm danh',
                          ),
                        ),
                      if (_isOpen || _viewState == _SessionViewState.closing)
                        FilledButton.tonalIcon(
                          onPressed: _isBusy ? null : _closeSession,
                          icon:
                              _viewState == _SessionViewState.closing
                                  ? const SizedBox.square(
                                    dimension: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                  : const Icon(Icons.stop),
                          label: const Text('Đóng phiên'),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SessionHeader extends StatelessWidget {
  final String className;
  final String lessonLabel;

  const _SessionHeader({required this.className, required this.lessonLabel});

  @override
  Widget build(BuildContext context) => Row(
    children: [
      CircleAvatar(
        radius: 26,
        child: Icon(
          Icons.co_present,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
      const SizedBox(width: 16),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(className, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 4),
            Text(lessonLabel, style: Theme.of(context).textTheme.bodyLarge),
          ],
        ),
      ),
    ],
  );
}

class _QrPanel extends StatelessWidget {
  final String? qrUrl;
  final _SessionViewState state;
  final Future<void> Function()? onRetry;

  const _QrPanel({required this.qrUrl, required this.state, this.onRetry});

  @override
  Widget build(BuildContext context) {
    if (qrUrl != null) {
      return DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: QrImageView(
            data: qrUrl!,
            version: QrVersions.auto,
            backgroundColor: Colors.white,
          ),
        ),
      );
    }
    if (state == _SessionViewState.open || state == _SessionViewState.opening) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            const Text('Đang tải mã QR...'),
            if (onRetry != null) ...[
              const SizedBox(height: 8),
              TextButton(onPressed: onRetry, child: const Text('Thử lại')),
            ],
          ],
        ),
      );
    }
    return Center(
      child: Icon(
        state == _SessionViewState.closed
            ? Icons.lock_outline
            : Icons.qr_code_2,
        size: 150,
        color: Theme.of(context).colorScheme.outline,
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final _SessionViewState state;

  const _StatusBadge({required this.state});

  @override
  Widget build(BuildContext context) {
    final isOpen = state == _SessionViewState.open;
    final label = switch (state) {
      _SessionViewState.idle => 'Chưa mở',
      _SessionViewState.opening => 'Đang mở...',
      _SessionViewState.open => 'Đang mở',
      _SessionViewState.closing => 'Đang đóng...',
      _SessionViewState.closed => 'Đã đóng',
    };
    final color = isOpen ? Colors.green : Theme.of(context).colorScheme.outline;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: color.withAlpha(24),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.circle, size: 10, color: color),
          const SizedBox(width: 7),
          Text(label),
        ],
      ),
    );
  }
}

class _ApiException implements Exception {
  final String message;
  const _ApiException(this.message);
}

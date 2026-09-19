import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:qr_flutter/qr_flutter.dart';

import '../../config.dart';
import '../../shared/m1_snackbar.dart';
import '../attendance/services/attendance_storage_service.dart';

enum _SessionViewState { idle, opening, open, closing, closed }

class QrDisplayScreen extends StatefulWidget {
  final String classId;
  final String sessionId;
  final String? className;
  final String? lessonLabel;
  final List<Map<String, dynamic>>? roster;
  final String apiBaseUrl;
  final http.Client? client;

  const QrDisplayScreen({
    super.key,
    required this.classId,
    required this.sessionId,
    this.className,
    this.lessonLabel,
    this.roster,
    this.apiBaseUrl = AppConfig.apiBaseUrl,
    this.client,
  });

  @override
  State<QrDisplayScreen> createState() => _QrDisplayScreenState();
}

class _QrDisplayScreenState extends State<QrDisplayScreen> {
  // Notion Academic Minimalist Palette
  static const _canvasBg = Color(0xFFFAF9F6);
  static const _borderColor = Color(0xFFE3E2DE);
  static const _textPrimary = Color(0xFF37352F);
  static const _textSecondary = Color(0xFF787774);

  late final http.Client _client;
  late final bool _ownsClient;
  Timer? _rotationTimer;
  Timer? _countdownTimer;
  Timer? _livePollingTimer;
  Timer? _sessionTimeoutTimer;

  _SessionViewState _viewState = _SessionViewState.idle;
  String? _windowId;
  String? _qrUrl;
  DateTime? _expiresAt;
  String? _errorMessage;
  int _secondsRemaining = 0;
  bool _isRefreshingQr = false;
  bool _isSyncingRemote = false;

  // 1. Dữ liệu sinh viên & Điểm danh realtime
  final List<Map<String, dynamic>> _rosterList = [];
  final Map<String, String> _studentStatus = {}; // email -> 'P' / 'A'
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String _statusFilter = 'all'; // 'all', 'present', 'absent'

  // 2. Thiết lập thời gian (Time settings)
  int _qrRefreshSeconds = 15; // 10, 15, 30, 60 giây
  int? _sessionDurationMinutes = 15; // 5, 10, 15, 30 phút hoặc null (không giới hạn)
  int _sessionRemainingSeconds = 0;

  // 3. Toàn màn hình (Fullscreen Presentation)
  bool _isFullscreen = false;

  bool get _isOpen => _viewState == _SessionViewState.open;
  bool get _isBusy =>
      _viewState == _SessionViewState.opening ||
      _viewState == _SessionViewState.closing;

  @override
  void initState() {
    super.initState();
    _ownsClient = widget.client == null;
    _client = widget.client ?? http.Client();

    _initRosterData();
    _loadInitialAttendance();
  }

  @override
  void dispose() {
    _stopTimers();
    _livePollingTimer?.cancel();
    _sessionTimeoutTimer?.cancel();
    _searchController.dispose();
    if (_ownsClient) _client.close();
    super.dispose();
  }

  int _resolveSlotSequence() {
    if (widget.lessonLabel != null) {
      final m = RegExp(r'(\d+)').firstMatch(widget.lessonLabel!);
      if (m != null) return int.tryParse(m.group(1)!) ?? 1;
    }
    final match = RegExp(r'(\d+)$').firstMatch(widget.sessionId);
    return match != null ? int.tryParse(match.group(1)!) ?? 1 : 1;
  }

  Map<int, Map<String, String>> _resolveClassStore(
    Map<String, Map<int, Map<String, String>>> store,
  ) {
    final candidateKeys = <String>[
      if (widget.className != null && widget.className!.isNotEmpty) widget.className!,
      widget.classId,
      if (widget.className != null && widget.className!.contains(' - ')) ...[
        widget.className!.split(' - ').last.trim(),
        widget.className!.split(' - ').first.trim(),
      ],
    ];

    for (final key in candidateKeys) {
      if (store.containsKey(key)) {
        return store[key]!;
      }
    }

    final fallback = widget.className ?? widget.classId;
    return store.putIfAbsent(fallback, () => <int, Map<String, String>>{});
  }

  void _syncClassStoreToAliases(
    Map<String, Map<int, Map<String, String>>> store,
    Map<int, Map<String, String>> classStore,
  ) {
    if (widget.className != null && widget.className!.isNotEmpty) {
      store[widget.className!] = classStore;
    }
    final candidateKeys = <String>[
      widget.classId,
      if (widget.className != null && widget.className!.contains(' - ')) ...[
        widget.className!.replaceAll(' - ', '_'),
        widget.className!.split(' - ').last.trim(),
        widget.className!.split(' - ').first.trim(),
      ],
    ];
    for (final existingKey in store.keys.toList()) {
      if (candidateKeys.contains(existingKey) ||
          existingKey.endsWith('_${widget.classId}') ||
          (widget.className != null &&
              existingKey.contains(widget.className!.replaceAll(' - ', '_')))) {
        store[existingKey] = classStore;
      }
    }
  }

  void _initRosterData() {
    if (widget.roster != null && widget.roster!.isNotEmpty) {
      for (final s in widget.roster!) {
        final email = (s['studentEmail'] ?? s['email'] ?? '').toString().trim().toLowerCase();
        _rosterList.add(Map<String, dynamic>.from(s));
        if (email.isNotEmpty) {
          _studentStatus.putIfAbsent(email, () => 'A');
        }
      }
    }
  }

  /// Nạp ngay dữ liệu điểm danh đã lưu trước đó của slot này (nếu có)
  Future<void> _loadInitialAttendance() async {
    try {
      final storage = AttendanceStorageService();
      final store = await storage.loadStore();
      final slotSeq = _resolveSlotSequence();
      final classAttendance = _resolveClassStore(store);
      final existingSlotData = classAttendance[slotSeq];

      if (existingSlotData != null && existingSlotData.isNotEmpty) {
        if (!mounted) return;
        setState(() {
          for (final entry in existingSlotData.entries) {
            final email = entry.key.trim().toLowerCase();
            final status = entry.value.trim().toUpperCase();
            if (status == 'P' || status == 'A') {
              _studentStatus[email] = status;
              if (email.isNotEmpty &&
                  !_rosterList.any((r) =>
                      (r['studentEmail'] ?? r['email'] ?? '').toString().trim().toLowerCase() == email)) {
                _rosterList.add({
                  'rollNumber': '',
                  'fullName': email,
                  'email': email,
                  'memberCode': '',
                });
              }
            }
          }
        });
      }
    } catch (_) {}

    // Tiếp tục đồng bộ realtime từ Google Sheet nếu có kết nối
    unawaited(_syncAttendanceToStorage(isSilent: true));
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
        if (_sessionDurationMinutes != null) {
          _sessionRemainingSeconds = _sessionDurationMinutes! * 60;
        } else {
          _sessionRemainingSeconds = 0;
        }
      });
      _startTimers();
      _startLivePolling();
      await _fetchQr();
      unawaited(_syncAttendanceToStorage(isSilent: true));
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _viewState = _SessionViewState.idle;
        _errorMessage = _friendlyError(error);
      });
    }
  }

  /// Đồng bộ 2 chiều từ Google Sheets về Desktop
  Future<void> _syncAttendanceToStorage({bool isSilent = false}) async {
    if (_isSyncingRemote) return;
    if (!isSilent && mounted) {
      setState(() => _isSyncingRemote = true);
    }
    try {
      final storage = AttendanceStorageService();
      final store = await storage.loadStore();

      final slotSeq = _resolveSlotSequence();
      final classStore = _resolveClassStore(store);

      final existingSlotData = classStore[slotSeq] ?? {};
      final slotMap = Map<String, String>.from(existingSlotData);

      // Điền các trạng thái đã lưu vào _studentStatus
      for (final entry in existingSlotData.entries) {
        final email = entry.key.trim().toLowerCase();
        final status = entry.value.trim().toUpperCase();
        if (status == 'P' || status == 'A') {
          _studentStatus[email] = status;
        }
      }

      // Kéo từ Google Sheets thông qua Backend API
      try {
        final uri = _endpoint('/session/${widget.sessionId}/attendances');
        final response = await _client.get(uri);
        if (response.statusCode == 200) {
          final data = jsonDecode(utf8.decode(response.bodyBytes));
          final payload = data['data'];
          if (payload != null && payload['students'] != null) {
            final students = payload['students'] as List;
            bool stateChanged = false;
            for (final s in students) {
              final email = (s['studentEmail'] ??
                      s['email'] ??
                      s['Email'] ??
                      s['StudentEmail'] ??
                      '')
                  .toString()
                  .trim()
                  .toLowerCase();
              final status = (s['status'] ?? s['Status'] ?? '').toString().trim().toUpperCase();

              if (email.isNotEmpty && (status == 'P' || status == 'A')) {
                slotMap[email] = status;
                if (_studentStatus[email] != status) {
                  _studentStatus[email] = status;
                  stateChanged = true;
                }
              }

              // Nếu danh sách lớp chưa có sinh viên này thì nạp thêm vào
              if (email.isNotEmpty &&
                  !_rosterList.any((r) =>
                      (r['studentEmail'] ?? r['email'] ?? '').toString().trim().toLowerCase() ==
                      email)) {
                _rosterList.add({
                  'rollNumber': s['rollNumber'] ?? s['RollNumber'] ?? '',
                  'fullName': s['fullName'] ?? s['FullName'] ?? email,
                  'email': email,
                  'memberCode': s['memberCode'] ?? s['MemberCode'] ?? '',
                });
                stateChanged = true;
              }
            }
            if (stateChanged && mounted) {
              setState(() {});
            }
          }
        }
      } catch (_) {}

      // Duy trì trạng thái đã có hoặc gán mặc định A nếu chưa từng điểm danh
      for (final student in _rosterList) {
        final email = (student['studentEmail'] ??
                student['email'] ??
                student['Email'] ??
                student['StudentEmail'] ??
                '')
            .toString()
            .trim()
            .toLowerCase();
        if (email.isNotEmpty) {
          final current = _studentStatus[email] ?? slotMap[email] ?? 'A';
          _studentStatus[email] = current;
          slotMap[email] = current;
        }
      }

      classStore[slotSeq] = slotMap;
      _syncClassStoreToAliases(store, classStore);
      await storage.saveStore(store);

      if (!isSilent && mounted) {
        M1SnackBar.show(context, 'Đã đồng bộ realtime với Google Sheet thành công!');
      }
    } catch (_) {
    } finally {
      if (!isSilent && mounted) {
        setState(() => _isSyncingRemote = false);
      }
    }
  }

  /// Giảng viên đổi điểm danh thủ công (Manual Override) -> Ghi ngay lên Google Sheets
  Future<void> _toggleStudentAttendance(String email, String studentName) async {
    final current = _studentStatus[email] ?? 'A';
    final nextStatus = current == 'P' ? 'A' : 'P';

    // 1. Cập nhật giao diện ngay tức thì (Optimistic UI)
    setState(() {
      _studentStatus[email] = nextStatus;
    });

    // 2. Lưu ngay vào local storage
    try {
      final storage = AttendanceStorageService();
      final store = await storage.loadStore();
      final slotSeq = _resolveSlotSequence();
      final classStore = _resolveClassStore(store);
      final slotMap = classStore.putIfAbsent(slotSeq, () => {});
      slotMap[email] = nextStatus;
      _syncClassStoreToAliases(store, classStore);
      await storage.saveStore(store);
    } catch (_) {}

    // 3. Gọi Backend API đẩy thẳng lên Google Sheet realtime
    try {
      final response = await _client.post(
        _endpoint('/attendance/manual-edit'),
        headers: const {'content-type': 'application/json'},
        body: jsonEncode({
          'sessionId': widget.sessionId,
          'studentEmail': email,
          'status': nextStatus,
        }),
      );
      if (response.statusCode == 200) {
        if (mounted) {
          final label = nextStatus == 'P' ? 'CÓ MẶT (P)' : 'VẮNG (A)';
          M1SnackBar.show(
            context,
            'Đã cập nhật $studentName -> $label (khớp với Google Sheet)',
          );
        }
      }
    } catch (e) {
      if (mounted) {
        M1SnackBar.show(
          context,
          'Đã lưu cục bộ. Lỗi kết nối đẩy lên Sheet: $e',
          type: M1NoticeType.warning,
        );
      }
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
      unawaited(_syncAttendanceToStorage(isSilent: true));
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
    _stopTimers();
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
      unawaited(_syncAttendanceToStorage(isSilent: true));
      setState(() {
        _viewState = _SessionViewState.closed;
        _qrUrl = null;
        _expiresAt = null;
        _secondsRemaining = 0;
        _sessionRemainingSeconds = 0;
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
      Duration(seconds: _qrRefreshSeconds),
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

    // Timer ca điểm danh tự động đóng khi hết giờ
    if (_sessionDurationMinutes != null) {
      _sessionTimeoutTimer?.cancel();
      _sessionTimeoutTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted || !_isOpen) {
          timer.cancel();
          return;
        }
        if (_sessionRemainingSeconds > 0) {
          setState(() {
            _sessionRemainingSeconds--;
          });
        } else {
          timer.cancel();
          unawaited(_closeSession());
          if (mounted) {
            M1SnackBar.show(
              context,
              'Thời gian ca điểm danh đã kết thúc. Phiên đã được tự động đóng.',
              type: M1NoticeType.warning,
            );
          }
        }
      });
    }
  }

  void _startLivePolling() {
    _livePollingTimer?.cancel();
    _livePollingTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (mounted && _isOpen) {
        unawaited(_syncAttendanceToStorage(isSilent: true));
      }
    });
  }

  void _stopTimers() {
    _rotationTimer?.cancel();
    _countdownTimer?.cancel();
    _sessionTimeoutTimer?.cancel();
    _rotationTimer = null;
    _countdownTimer = null;
    _sessionTimeoutTimer = null;
  }

  int _remainingSeconds(DateTime expiresAt) {
    final milliseconds = expiresAt
        .difference(DateTime.now().toUtc())
        .inMilliseconds;
    if (milliseconds <= 0) return 0;
    return (milliseconds / 1000).ceil().clamp(0, _qrRefreshSeconds).toInt();
  }

  Uri _endpoint(String path) {
    final base = Uri.parse(widget.apiBaseUrl);
    final normalizedBasePath = base.path.endsWith('/')
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

  List<Map<String, dynamic>> get _filteredRoster {
    final query = _searchQuery.trim().toLowerCase();
    return _rosterList.where((student) {
      final email = (student['studentEmail'] ?? student['email'] ?? '').toString().trim().toLowerCase();
      final name = (student['fullName'] ?? '').toString().toLowerCase();
      final roll = (student['rollNumber'] ?? '').toString().toLowerCase();
      final status = _studentStatus[email] ?? 'A';

      final matchesQuery = query.isEmpty ||
          email.contains(query) ||
          name.contains(query) ||
          roll.contains(query);

      if (!matchesQuery) return false;

      if (_statusFilter == 'present') return status == 'P';
      if (_statusFilter == 'absent') return status == 'A';
      return true;
    }).toList();
  }

  int get _presentCount => _rosterList.where((student) {
        final email = (student['studentEmail'] ?? student['email'] ?? '').toString().trim().toLowerCase();
        return (_studentStatus[email] ?? 'A') == 'P';
      }).length;
  int get _absentCount => _rosterList.length - _presentCount;

  @override
  Widget build(BuildContext context) {
    // 1. Chế độ Toàn Màn Hình Chiếu Máy Chiếu (Fullscreen Projector View)
    if (_isFullscreen) {
      return _buildFullscreenProjectorView();
    }

    // 2. Giao diện tiêu chuẩn Notion Split View (Cột QR bên trái & Cột SV bên phải)
    return Scaffold(
      backgroundColor: _canvasBg,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: _canvasBg,
        surfaceTintColor: Colors.transparent,
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, thickness: 1, color: _borderColor),
        ),
        title: Text(
          'Trình chiếu QR điểm danh',
          style: GoogleFonts.inter(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: _textPrimary,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Trình chiếu toàn màn hình (Projector)',
            icon: const Icon(Icons.fullscreen, size: 20, color: _textPrimary),
            onPressed: () => setState(() => _isFullscreen = true),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(child: _StatusBadge(state: _viewState)),
          ),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 940;

            if (isWide) {
              return Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Cột Trái: QR, Bộ Đếm, Nút Thao Tác & Cài Đặt (420px)
                    SizedBox(
                      width: 420,
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _SessionHeader(
                              className: widget.className ?? widget.classId,
                              lessonLabel: widget.lessonLabel ?? widget.sessionId,
                            ),
                            const SizedBox(height: 12),
                            _buildTimeSettingsCard(),
                            const SizedBox(height: 12),
                            _buildQrCard(),
                            if (_errorMessage != null) ...[
                              const SizedBox(height: 12),
                              _buildErrorBanner(),
                            ],
                            const SizedBox(height: 12),
                            _buildActionButtons(),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    // Cột Phải: Bảng Sinh Viên & Điểm Danh Realtime
                    Expanded(
                      child: _buildRosterPanel(),
                    ),
                  ],
                ),
              );
            }

            // Màn hình hẹp: Dạng cột cuộn dọc
            return SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _SessionHeader(
                    className: widget.className ?? widget.classId,
                    lessonLabel: widget.lessonLabel ?? widget.sessionId,
                  ),
                  const SizedBox(height: 12),
                  _buildTimeSettingsCard(),
                  const SizedBox(height: 12),
                  _buildQrCard(),
                  if (_errorMessage != null) ...[
                    const SizedBox(height: 12),
                    _buildErrorBanner(),
                  ],
                  const SizedBox(height: 12),
                  _buildActionButtons(),
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 520,
                    child: _buildRosterPanel(),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildTimeSettingsCard() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: _borderColor, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.timer_outlined, size: 15, color: _textSecondary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Thiết Lập Thời Gian',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: _textPrimary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (_isOpen && _sessionDurationMinutes != null) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF3C7),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: const Color(0xFFFCD34D), width: 0.8),
                  ),
                  child: Text(
                    'Đóng sau: ${_formatDuration(_sessionRemainingSeconds)}',
                    style: GoogleFonts.inter(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFFB45309),
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          // 1. Chu kỳ xoay QR
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 4,
            runSpacing: 4,
            children: [
              Text(
                'Xoay mã QR:',
                style: GoogleFonts.inter(fontSize: 11, color: _textSecondary),
              ),
              _timePill(10, '10s', _qrRefreshSeconds == 10, (val) {
                setState(() => _qrRefreshSeconds = val);
                if (_isOpen) _startTimers();
              }),
              _timePill(15, '15s', _qrRefreshSeconds == 15, (val) {
                setState(() => _qrRefreshSeconds = val);
                if (_isOpen) _startTimers();
              }),
              _timePill(30, '30s', _qrRefreshSeconds == 30, (val) {
                setState(() => _qrRefreshSeconds = val);
                if (_isOpen) _startTimers();
              }),
              _timePill(60, '60s', _qrRefreshSeconds == 60, (val) {
                setState(() => _qrRefreshSeconds = val);
                if (_isOpen) _startTimers();
              }),
            ],
          ),
          const SizedBox(height: 6),
          // 2. Thời lượng ca điểm danh
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 4,
            runSpacing: 4,
            children: [
              Text(
                'Thời lượng ca:',
                style: GoogleFonts.inter(fontSize: 11, color: _textSecondary),
              ),
              _durationPill(5, '5p', _sessionDurationMinutes == 5, (val) {
                setState(() => _sessionDurationMinutes = val);
              }),
              _durationPill(10, '10p', _sessionDurationMinutes == 10, (val) {
                setState(() => _sessionDurationMinutes = val);
              }),
              _durationPill(15, '15p', _sessionDurationMinutes == 15, (val) {
                setState(() => _sessionDurationMinutes = val);
              }),
              _durationPill(30, '30p', _sessionDurationMinutes == 30, (val) {
                setState(() => _sessionDurationMinutes = val);
              }),
              _durationPill(null, 'Vô hạn', _sessionDurationMinutes == null, (val) {
                setState(() => _sessionDurationMinutes = val);
              }),
            ],
          ),
        ],
      ),
    );
  }

  Widget _timePill(int value, String label, bool isSelected, ValueChanged<int> onSelect) {
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: InkWell(
        onTap: () => onSelect(value),
        borderRadius: BorderRadius.circular(3),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: isSelected ? _textPrimary : const Color(0xFFF7F6F3),
            borderRadius: BorderRadius.circular(3),
            border: Border.all(
              color: isSelected ? _textPrimary : _borderColor,
              width: 0.8,
            ),
          ),
          child: Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 10.5,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
              color: isSelected ? Colors.white : _textPrimary,
            ),
          ),
        ),
      ),
    );
  }

  Widget _durationPill(int? value, String label, bool isSelected, ValueChanged<int?> onSelect) {
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: InkWell(
        onTap: () => onSelect(value),
        borderRadius: BorderRadius.circular(3),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: isSelected ? _textPrimary : const Color(0xFFF7F6F3),
            borderRadius: BorderRadius.circular(3),
            border: Border.all(
              color: isSelected ? _textPrimary : _borderColor,
              width: 0.8,
            ),
          ),
          child: Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 10.5,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
              color: isSelected ? Colors.white : _textPrimary,
            ),
          ),
        ),
      ),
    );
  }

  String _formatDuration(int totalSeconds) {
    final m = totalSeconds ~/ 60;
    final s = totalSeconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  Widget _buildQrCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: _borderColor, width: 1),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          SizedBox(
            width: 260,
            height: 260,
            child: _QrPanel(
              qrUrl: _qrUrl,
              state: _viewState,
              onRetry: _isOpen ? _fetchQr : null,
            ),
          ),
          const SizedBox(height: 16),
          if (_isOpen) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(
                    color: Color(0xFF1F7A4D),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'Mã mới sau $_secondsRemaining giây',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: _textPrimary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: 260,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: _qrRefreshSeconds > 0 ? (_secondsRemaining / _qrRefreshSeconds) : 0,
                  minHeight: 4,
                  backgroundColor: const Color(0xFFEFEFED),
                  valueColor: const AlwaysStoppedAnimation<Color>(_textPrimary),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Sinh viên quét mã bằng camera điện thoại để mở trang điểm danh.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 11.5,
                color: _textSecondary,
              ),
            ),
            if (_qrUrl != null && _qrUrl!.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFFF7F6F3),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: _borderColor, width: 1),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.link, size: 14, color: _textSecondary),
                    const SizedBox(width: 6),
                    Expanded(
                      child: SelectableText(
                        _qrUrl!,
                        maxLines: 1,
                        style: GoogleFonts.robotoMono(fontSize: 11, color: _textPrimary),
                      ),
                    ),
                    const SizedBox(width: 6),
                    InkWell(
                      borderRadius: BorderRadius.circular(3),
                      onTap: () {
                        Clipboard.setData(ClipboardData(text: _qrUrl!));
                        M1SnackBar.show(context, 'Đã sao chép link điểm danh vào bộ nhớ tạm!');
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(3),
                          border: Border.all(color: _borderColor, width: 0.8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.copy, size: 12, color: _textPrimary),
                            const SizedBox(width: 4),
                            Text(
                              'Sao chép link',
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                                color: _textPrimary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ] else
            Text(
              _viewState == _SessionViewState.closed
                  ? 'Phiên đã đóng. Kết quả hiện tại được giữ nguyên.'
                  : 'Mở phiên để khởi tạo điểm A và bắt đầu trình chiếu QR.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(fontSize: 12.5, color: _textSecondary),
            ),
        ],
      ),
    );
  }

  Widget _buildErrorBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFFEE2E2),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: const Color(0xFFFECACA)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, size: 15, color: Color(0xFFB91C1C)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _errorMessage!,
              style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFFB91C1C)),
            ),
          ),
          InkWell(
            onTap: () => setState(() => _errorMessage = null),
            child: const Text(
              'Đóng',
              style: TextStyle(
                fontSize: 11.5,
                color: Color(0xFFB91C1C),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: WrapAlignment.center,
      children: [
        if (!_isOpen && _viewState != _SessionViewState.closing)
          InkWell(
            onTap: _isBusy ? null : _openSession,
            borderRadius: BorderRadius.circular(4),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: _isBusy ? const Color(0xFF787774) : _textPrimary,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_viewState == _SessionViewState.opening)
                    const SizedBox.square(
                      dimension: 13,
                      child: CircularProgressIndicator(strokeWidth: 1.8, color: Colors.white),
                    )
                  else
                    const Icon(Icons.play_arrow, size: 15, color: Colors.white),
                  const SizedBox(width: 6),
                  Text(
                    _viewState == _SessionViewState.closed ? 'Mở lại phiên' : 'Mở phiên điểm danh',
                    style: GoogleFonts.inter(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),
        if (_isOpen || _viewState == _SessionViewState.closing)
          InkWell(
            onTap: _isBusy ? null : _closeSession,
            borderRadius: BorderRadius.circular(4),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: const Color(0xFFDC2626), width: 1),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_viewState == _SessionViewState.closing)
                    const SizedBox.square(
                      dimension: 13,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.8,
                        color: Color(0xFFDC2626),
                      ),
                    )
                  else
                    const Icon(Icons.stop, size: 15, color: Color(0xFFDC2626)),
                  const SizedBox(width: 6),
                  Text(
                    'Đóng phiên',
                    style: GoogleFonts.inter(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFFDC2626),
                    ),
                  ),
                ],
              ),
            ),
          ),
        // Nút Toàn màn hình
        InkWell(
          onTap: () => setState(() => _isFullscreen = true),
          borderRadius: BorderRadius.circular(4),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: _borderColor, width: 1),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.fullscreen, size: 15, color: _textPrimary),
                const SizedBox(width: 5),
                Text(
                  'Toàn Màn Hình',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: _textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ),
        // Nút Đồng bộ Google Sheet
        InkWell(
          onTap: _isSyncingRemote ? null : () => _syncAttendanceToStorage(isSilent: false),
          borderRadius: BorderRadius.circular(4),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: _borderColor, width: 1),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_isSyncingRemote)
                  const SizedBox.square(
                    dimension: 13,
                    child: CircularProgressIndicator(strokeWidth: 1.8, color: _textPrimary),
                  )
                else
                  const Icon(Icons.sync, size: 15, color: _textPrimary),
                const SizedBox(width: 5),
                Text(
                  _isSyncingRemote ? 'Đang đồng bộ...' : 'Đồng Bộ Sheet',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: _textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// Cột Phải: Bảng Sinh Viên và Điểm Danh Trực Tiếp
  Widget _buildRosterPanel() {
    final filtered = _filteredRoster;
    final total = _rosterList.length;
    final present = _presentCount;
    final absent = _absentCount;
    final rate = total > 0 ? (present / total * 100).toStringAsFixed(1) : '0';

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: _borderColor, width: 1),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. Thẻ tóm tắt Sĩ số & Trực tiếp
          Row(
            children: [
              _statTile('Sĩ Số Lớp', '$total SV', const Color(0xFFF7F6F3), _textPrimary),
              const SizedBox(width: 8),
              _statTile('Có Mặt (P)', '$present ($rate%)', const Color(0xFFEBF5F0), const Color(0xFF1F7A4D)),
              const SizedBox(width: 8),
              _statTile('Vắng (A)', '$absent', const Color(0xFFFDF5E6), const Color(0xFFB45309)),
            ],
          ),
          const SizedBox(height: 12),

          // 2. Ô tìm kiếm & Bộ lọc
          Row(
            children: [
              Expanded(
                child: Container(
                  height: 32,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: _borderColor),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.search, size: 14, color: _textSecondary),
                      const SizedBox(width: 6),
                      Expanded(
                        child: TextField(
                          controller: _searchController,
                          onChanged: (val) => setState(() => _searchQuery = val),
                          style: GoogleFonts.inter(fontSize: 12, color: _textPrimary),
                          decoration: InputDecoration(
                            hintText: 'Tìm theo MSSV hoặc Họ Tên...',
                            hintStyle: GoogleFonts.inter(fontSize: 11, color: _textSecondary),
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _filterTab('Tất cả', 'all', _statusFilter == 'all'),
              const SizedBox(width: 4),
              _filterTab('Có mặt ($present)', 'present', _statusFilter == 'present'),
              const SizedBox(width: 4),
              _filterTab('Vắng ($absent)', 'absent', _statusFilter == 'absent'),
            ],
          ),
          const SizedBox(height: 10),

          // 3. Bảng Danh Sách Sinh Viên
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: _borderColor, width: 0.8),
              ),
              child: filtered.isEmpty
                  ? Center(
                      child: Text(
                        'Không có sinh viên nào khớp kết quả tìm kiếm.',
                        style: GoogleFonts.inter(fontSize: 12, color: _textSecondary),
                      ),
                    )
                  : ListView.separated(
                      itemCount: filtered.length,
                      separatorBuilder: (_, _) =>
                          const Divider(height: 1, thickness: 0.8, color: _borderColor),
                      itemBuilder: (context, index) {
                        final s = filtered[index];
                        final email = (s['studentEmail'] ?? s['email'] ?? '').toString().trim().toLowerCase();
                        final rollNumber = (s['rollNumber'] ?? '').toString();
                        final fullName = (s['fullName'] ?? email).toString();
                        final status = _studentStatus[email] ?? 'A';
                        final isPresent = status == 'P';

                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          child: Row(
                            children: [
                              // MSSV
                              SizedBox(
                                width: 90,
                                child: Text(
                                  rollNumber,
                                  style: GoogleFonts.inter(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: _textPrimary,
                                  ),
                                ),
                              ),
                              // Họ và Tên
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      fullName,
                                      style: GoogleFonts.inter(
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w500,
                                        color: _textPrimary,
                                      ),
                                    ),
                                    Text(
                                      email,
                                      style: GoogleFonts.inter(
                                        fontSize: 11,
                                        color: _textSecondary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              // Badge Trạng thái
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: isPresent
                                      ? const Color(0xFFEBF5F0)
                                      : const Color(0xFFFDF5E6),
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(
                                    color: isPresent
                                        ? const Color(0xFFC6E7D6)
                                        : const Color(0xFFFCD34D),
                                    width: 0.8,
                                  ),
                                ),
                                child: Text(
                                  isPresent ? 'Có Mặt (P)' : 'Vắng (A)',
                                  style: GoogleFonts.inter(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: isPresent
                                        ? const Color(0xFF1F7A4D)
                                        : const Color(0xFFB45309),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              // Nút Giảng viên click đổi điểm danh (Manual Toggle)
                              InkWell(
                                onTap: () => _toggleStudentAttendance(email, fullName),
                                borderRadius: BorderRadius.circular(3),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isPresent ? Colors.white : _textPrimary,
                                    borderRadius: BorderRadius.circular(3),
                                    border: Border.all(
                                      color: isPresent ? _borderColor : _textPrimary,
                                      width: 1,
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        isPresent ? Icons.close : Icons.check,
                                        size: 12,
                                        color: isPresent ? _textSecondary : Colors.white,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        isPresent ? 'Đánh vắng' : 'Điểm danh',
                                        style: GoogleFonts.inter(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w500,
                                          color: isPresent ? _textSecondary : Colors.white,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statTile(String label, String value, Color bg, Color text) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: _borderColor, width: 0.8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: GoogleFonts.inter(fontSize: 10.5, color: _textSecondary),
            ),
            const SizedBox(height: 2),
            Text(
              value,
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: text,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _filterTab(String label, String value, bool isSelected) {
    return InkWell(
      onTap: () => setState(() => _statusFilter = value),
      borderRadius: BorderRadius.circular(3),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected ? _textPrimary : const Color(0xFFF7F6F3),
          borderRadius: BorderRadius.circular(3),
          border: Border.all(
            color: isSelected ? _textPrimary : _borderColor,
            width: 0.8,
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
            color: isSelected ? Colors.white : _textPrimary,
          ),
        ),
      ),
    );
  }

  /// Chế Độ Trình Chiếu Toàn Màn Hình Máy Chiếu (Fullscreen Projector View)
  Widget _buildFullscreenProjectorView() {
    final present = _presentCount;
    final total = _rosterList.length;
    final rate = total > 0 ? (present / total * 100).toStringAsFixed(1) : '0';

    return Scaffold(
      backgroundColor: const Color(0xFF1E1E1E),
      body: SafeArea(
        child: Stack(
          children: [
            // Nội dung trung tâm
            Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.className ?? widget.classId,
                      style: GoogleFonts.inter(
                        fontSize: 32,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${widget.lessonLabel ?? widget.sessionId} • Điểm Danh Trực Tiếp',
                      style: GoogleFonts.inter(
                        fontSize: 16,
                        fontWeight: FontWeight.w400,
                        color: const Color(0xFFA0A0A0),
                      ),
                    ),
                    const SizedBox(height: 24),
                    // Mã QR to rõ nét
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withAlpha(80),
                            blurRadius: 30,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      padding: const EdgeInsets.all(28),
                      child: SizedBox(
                        width: 360,
                        height: 360,
                        child: _QrPanel(
                          qrUrl: _qrUrl,
                          state: _viewState,
                          onRetry: _isOpen ? _fetchQr : null,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    if (_isOpen) ...[
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: Color(0xFF22C55E),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            'Mã đổi sau $_secondsRemaining giây',
                            style: GoogleFonts.inter(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: 360,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: _qrRefreshSeconds > 0 ? (_secondsRemaining / _qrRefreshSeconds) : 0,
                            minHeight: 6,
                            backgroundColor: const Color(0xFF333333),
                            valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF22C55E)),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                    // Ticker Thống kê trực tiếp
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF2B2B2B),
                        borderRadius: BorderRadius.circular(30),
                        border: Border.all(color: const Color(0xFF404040)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.people_outline, size: 18, color: Colors.white),
                          const SizedBox(width: 8),
                          Text(
                            'Đã điểm danh: $present / $total sinh viên ($rate%)',
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                          if (_sessionDurationMinutes != null && _sessionRemainingSeconds > 0) ...[
                            const SizedBox(width: 16),
                            Container(width: 1, height: 16, color: const Color(0xFF555555)),
                            const SizedBox(width: 16),
                            const Icon(Icons.timer_outlined, size: 16, color: Color(0xFFFBBF24)),
                            const SizedBox(width: 6),
                            Text(
                              'Đóng ca sau: ${_formatDuration(_sessionRemainingSeconds)}',
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: const Color(0xFFFBBF24),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Nút Thoát toàn màn hình ở góc trên phải
            Positioned(
              top: 20,
              right: 20,
              child: InkWell(
                onTap: () => setState(() => _isFullscreen = false),
                borderRadius: BorderRadius.circular(6),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF333333),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: const Color(0xFF4A4A4A)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.fullscreen_exit, size: 18, color: Colors.white),
                      const SizedBox(width: 6),
                      Text(
                        'Thoát toàn màn hình',
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
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
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFFE3E2DE), width: 1),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: const Color(0xFFF7F6F3),
              borderRadius: BorderRadius.circular(5),
              border: Border.all(color: const Color(0xFFE3E2DE), width: 1),
            ),
            alignment: Alignment.center,
            child: const Icon(
              Icons.qr_code_2_outlined,
              size: 18,
              color: Color(0xFF37352F),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  className,
                  style: GoogleFonts.inter(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF37352F),
                    letterSpacing: -0.2,
                  ),
                ),
                Text(
                  lessonLabel,
                  style: GoogleFonts.inter(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w400,
                    color: const Color(0xFF787774),
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: const Color(0xFFF7F6F3),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: const Color(0xFFE3E2DE), width: 0.8),
            ),
            child: Text(
              'Trực Tiếp',
              style: GoogleFonts.inter(
                fontSize: 10.5,
                fontWeight: FontWeight.w500,
                color: const Color(0xFF787774),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _QrPanel extends StatelessWidget {
  final String? qrUrl;
  final _SessionViewState state;
  final Future<void> Function()? onRetry;

  const _QrPanel({required this.qrUrl, required this.state, this.onRetry});

  @override
  Widget build(BuildContext context) {
    if (qrUrl != null) {
      return Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFE3E2DE), width: 1),
        ),
        padding: const EdgeInsets.all(16),
        child: QrImageView(
          data: qrUrl!,
          version: QrVersions.auto,
          backgroundColor: Colors.white,
        ),
      );
    }
    if (state == _SessionViewState.open || state == _SessionViewState.opening) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox.square(
              dimension: 26,
              child: CircularProgressIndicator(
                strokeWidth: 2.2,
                color: Color(0xFF37352F),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Đang tải mã QR...',
              style: GoogleFonts.inter(
                fontSize: 12.5,
                color: const Color(0xFF787774),
              ),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 8),
              TextButton(
                onPressed: onRetry,
                child: Text(
                  'Thử lại',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: const Color(0xFF37352F),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
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
        size: 110,
        color: const Color(0xFFD3D1CB),
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

    final isClosed = state == _SessionViewState.closed;
    final dotColor = isOpen
        ? const Color(0xFF1F7A4D)
        : (isClosed ? const Color(0xFF787774) : const Color(0xFFB45309));
    final bgColor = isOpen
        ? const Color(0xFFEBF5F0)
        : (isClosed ? const Color(0xFFF7F6F3) : const Color(0xFFFEF3C7));
    final borderColor = isOpen
        ? const Color(0xFFC6E7D6)
        : (isClosed ? const Color(0xFFE3E2DE) : const Color(0xFFFCD34D));
    final textColor = isOpen
        ? const Color(0xFF1F7A4D)
        : (isClosed ? const Color(0xFF787774) : const Color(0xFFB45309));

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: borderColor, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: dotColor,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: textColor,
            ),
          ),
        ],
      ),
    );
  }
}

class _ApiException implements Exception {
  final String message;
  const _ApiException(this.message);
}


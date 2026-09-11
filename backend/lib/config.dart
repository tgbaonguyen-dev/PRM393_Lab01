import 'dart:io';

class AppConfig {
  static final String appsScriptGatewayUrl = Platform.environment['APPS_SCRIPT_GATEWAY_URL'] ??
      'https://script.google.com/macros/s/AKfycbxuAV49xcKSzJHeiyRZ96LEj_qwLLP_omiJu5XTXbCo-xdRg0G7KhE9SNZI_y28r21ftw/exec';

  static final String qrHmacSecret = Platform.environment['QR_HMAC_SECRET'] ??
      'dev-secret-key-prm393-attendance';

  static final int port = int.tryParse(Platform.environment['PORT'] ?? '8080') ?? 8080;
}

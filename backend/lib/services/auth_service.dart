import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

class GoogleTokenPayload {
  final String email;
  final bool emailVerified;
  final String? name;
  final String? subject;

  const GoogleTokenPayload({
    required this.email,
    required this.emailVerified,
    this.name,
    this.subject,
  });

  factory GoogleTokenPayload.fromJson(Map<String, dynamic> json) {
    final verified = json['email_verified'];
    return GoogleTokenPayload(
      email: (json['email'] as String? ?? '').trim().toLowerCase(),
      emailVerified: verified == true || verified == 'true',
      name: json['name'] as String?,
      subject: json['sub'] as String?,
    );
  }
}

class AuthService {
  final http.Client _client;
  final String? expectedClientId;

  AuthService({http.Client? client, String? expectedClientId})
      : _client = client ?? http.Client(),
        expectedClientId =
            expectedClientId ?? Platform.environment['GOOGLE_CLIENT_ID'];

  Future<GoogleTokenPayload?> verifyGoogleIdToken(String idToken) async {
    final token = idToken.trim();
    if (token.isEmpty) return null;

    if (Platform.environment['ALLOW_MOCK_GOOGLE_TOKEN'] == 'true' &&
        token.startsWith('mock_id_token_')) {
      final parts = token.split('_');
      final email = parts.length >= 4 ? parts[3].trim().toLowerCase() : '';
      if (email.isEmpty || !email.contains('@')) return null;
      return GoogleTokenPayload(
        email: email,
        emailVerified: true,
        name: email.split('@').first,
        subject: 'mock-subject',
      );
    }

    final clientId = expectedClientId?.trim() ?? '';
    if (clientId.isEmpty) return null;

    try {
      final response = await _client.get(
        Uri.https('oauth2.googleapis.com', '/tokeninfo', {'id_token': token}),
      );
      if (response.statusCode != 200) return null;

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) return null;

      final payload = GoogleTokenPayload.fromJson(decoded);
      final expiry = int.tryParse(decoded['exp']?.toString() ?? '');
      final audience = decoded['aud']?.toString();
      if (payload.email.isEmpty ||
          !payload.emailVerified ||
          expiry == null ||
          expiry <= DateTime.now().millisecondsSinceEpoch ~/ 1000 ||
          audience != clientId) {
        return null;
      }
      return payload;
    } catch (_) {
      return null;
    }
  }

  bool isStudentInRoster({
    required String email,
    required List<Map<String, dynamic>> roster,
  }) {
    final normalizedEmail = email.trim().toLowerCase();
    return normalizedEmail.isNotEmpty &&
        roster.any(
          (student) =>
              (student['email'] as String? ?? '').trim().toLowerCase() ==
              normalizedEmail,
        );
  }
}

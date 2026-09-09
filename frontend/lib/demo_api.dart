import 'dart:convert';

import 'package:http/http.dart' as http;

import 'config.dart';

class DemoApi {
  Future<String> fetchMessage() async {
    final response = await http
        .get(
          Uri.parse(
            '${AppConfig.apiBaseUrl.replaceFirst(RegExp(r"/+$"), "")}/api/demo',
          ),
        )
        .timeout(const Duration(seconds: 10));

    if (response.statusCode != 200) {
      throw Exception('Backend returned HTTP ${response.statusCode}.');
    }
    final data = jsonDecode(response.body);
    if (data is! Map<String, dynamic> || data['message'] is! String) {
      throw const FormatException('Unexpected API response.');
    }
    return data['message'] as String;
  }
}

import 'dart:io';

/// Loads only local development configuration. Production configuration should
/// be injected by the host as real environment variables.
class LocalEnv {
  static Future<Map<String, String>> load() async {
    final values = <String, String>{...Platform.environment};
    final candidates = [
      File('.env.local'),
      File('../.env.local'),
    ];
    final file =
        candidates.where((candidate) => candidate.existsSync()).firstOrNull;
    if (file == null) return values;

    for (final rawLine in await file.readAsLines()) {
      final line = rawLine.trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      final separator = line.indexOf('=');
      if (separator <= 0) continue;
      final key = line.substring(0, separator).trim();
      final value = line.substring(separator + 1).trim();
      if (key.isNotEmpty && !values.containsKey(key)) values[key] = value;
    }
    return values;
  }
}

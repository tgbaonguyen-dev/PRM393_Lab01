class DemoService {
  Map<String, String> getMessage() => {
    'message': 'Hello from the Dart backend!',
    'serverTime': DateTime.now().toUtc().toIso8601String(),
  };
}

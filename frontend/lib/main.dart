import 'package:flutter/material.dart';

import 'demo_api.dart';

void main() => runApp(const MainApp());

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'PRM393 Attendance',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.indigo),
    home: const DemoPage(),
  );
}

class DemoPage extends StatefulWidget {
  const DemoPage({super.key});

  @override
  State<DemoPage> createState() => _DemoPageState();
}

class _DemoPageState extends State<DemoPage> {
  final _api = DemoApi();
  bool _loading = false;
  bool _failed = false;
  String? _message;

  Future<void> _checkConnection() async {
    setState(() {
      _loading = true;
      _failed = false;
      _message = null;
    });
    try {
      final message = await _api.fetchMessage();
      if (!mounted) return;
      setState(() => _message = message);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _failed = true;
        _message =
            'Could not reach the backend. Check that it is running, then try again.';
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.calendar_month_outlined, size: 48),
                const SizedBox(height: 20),
                Text(
                  'PRM393 Attendance',
                  style: Theme.of(context).textTheme.headlineMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                const Text(
                  'Check the connection to your backend.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: _loading ? null : _checkConnection,
                  icon: _loading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.sync),
                  label: Text(_loading ? 'Connecting...' : 'Check connection'),
                ),
                if (_message != null) ...[
                  const SizedBox(height: 24),
                  Semantics(
                    liveRegion: true,
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          children: [
                            Icon(
                              _failed
                                  ? Icons.error_outline
                                  : Icons.check_circle_outline,
                              color: _failed
                                  ? Theme.of(context).colorScheme.error
                                  : Colors.green,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _failed ? 'Connection failed' : 'Connected',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 8),
                            Text(_message!, textAlign: TextAlign.center),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

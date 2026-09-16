import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prm393_desktop/shared/m1_snackbar.dart';

void main() {
  for (final entry in <M1NoticeType, Color>{
    M1NoticeType.success: Colors.green.shade700,
    M1NoticeType.warning: Colors.amber.shade800,
    M1NoticeType.error: Colors.red.shade700,
  }.entries) {
    testWidgets(
      '${entry.key.name} notice uses its color and ten-second timeout',
      (tester) async {
        late BuildContext pageContext;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) {
                  pageContext = context;
                  return const SizedBox();
                },
              ),
            ),
          ),
        );

        M1SnackBar.show(pageContext, 'Thông báo', type: entry.key);
        await tester.pumpAndSettle();

        final snackBar = tester.widget<SnackBar>(find.byType(SnackBar));
        expect(snackBar.duration, const Duration(seconds: 10));
        expect(snackBar.backgroundColor, entry.value);

        await tester.pump(const Duration(seconds: 10));
        await tester.pumpAndSettle();
      },
    );
  }

  testWidgets('notice closes after ten seconds with accessible navigation', (
    tester,
  ) async {
    late BuildContext pageContext;
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(accessibleNavigation: true),
          child: Scaffold(
            body: Builder(
              builder: (context) {
                pageContext = context;
                return const SizedBox();
              },
            ),
          ),
        ),
      ),
    );

    M1SnackBar.show(pageContext, 'Thông báo');
    await tester.pump();
    expect(find.byType(SnackBar), findsOneWidget);

    await tester.pump(const Duration(seconds: 10));
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsNothing);
  });
}

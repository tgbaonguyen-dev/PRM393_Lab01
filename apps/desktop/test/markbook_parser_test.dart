import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:prm393_desktop/features/markbook_import/services/markbook_parser.dart';

void main() {
  test('Parse FA26_Markbook.ods', () async {
    final file = File('../../sample_data/FA26_Markbook.ods');
    expect(file.existsSync(), isTrue);

    final parser = MarkbookParser();
    final results = await parser.parseFile(file);

    expect(results.length, equals(8));
    for (final r in results) {
      expect(r.roster.isNotEmpty, isTrue);
    }
  });
}

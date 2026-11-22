import 'package:acervo_hc/src/utils/date_util.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';

void main() {
  test('DateUtil.transformUtc2LocalTimeString matches DateFormat conversion and caches result', () {
    const String sample = '2026-11-20 18:45';
    final DateTime expectedLocal = DateFormat('yyyy-MM-dd HH:mm', 'en_US').parseUtc(sample).toLocal();
    final String expected = DateFormat('yyyy-MM-dd HH:mm').format(expectedLocal);

    expect(DateUtil.transformUtc2LocalTimeString(sample), expected);
    expect(DateUtil.transformUtc2LocalTimeString(sample), expected);
  });

  test('DateUtil.transformUtc2LocalTimeString safely handles empty and partial timestamps', () {
    expect(DateUtil.transformUtc2LocalTimeString(''), '');
    expect(DateUtil.transformUtc2LocalTimeString('   '), '');
    expect(DateUtil.transformUtc2LocalTimeString('2026-11-22'), '2026-11-22');
  });
}

import 'package:intl/intl.dart';

class DateUtil {
  static final DateFormat _utcFormat = DateFormat('yyyy-MM-dd HH:mm', 'en_US');
  static final DateFormat _localFormat = DateFormat('yyyy-MM-dd HH:mm');
  static final Map<String, String> _localTimeCache = <String, String>{};
  static const int _maxCacheEntries = 2000;

  /// Converts an E-H UTC timestamp (`yyyy-MM-dd HH:mm`) to local time.
  ///
  /// Memoized and parsed directly without instantiating [DateFormat] on every
  /// gallery card build.
  static String transformUtc2LocalTimeString(String utcTimeString) {
    final String? cached = _localTimeCache[utcTimeString];
    if (cached != null) {
      return cached;
    }

    final String result = _convert(utcTimeString);
    if (_localTimeCache.length >= _maxCacheEntries) {
      _localTimeCache.clear();
    }
    _localTimeCache[utcTimeString] = result;
    return result;
  }

  static String _convert(String utcTimeString) {
    /// Fast path for canonical `yyyy-MM-dd HH:mm` (16 chars) without intl overhead.
    if (utcTimeString.length == 16 &&
        utcTimeString.codeUnitAt(4) == 0x2D &&
        utcTimeString.codeUnitAt(7) == 0x2D &&
        utcTimeString.codeUnitAt(10) == 0x20 &&
        utcTimeString.codeUnitAt(13) == 0x3A) {
      final int? year = int.tryParse(utcTimeString.substring(0, 4));
      final int? month = int.tryParse(utcTimeString.substring(5, 7));
      final int? day = int.tryParse(utcTimeString.substring(8, 10));
      final int? hour = int.tryParse(utcTimeString.substring(11, 13));
      final int? minute = int.tryParse(utcTimeString.substring(14, 16));
      if (year != null && month != null && day != null && hour != null && minute != null) {
        final DateTime local = DateTime.utc(year, month, day, hour, minute).toLocal();
        return '${local.year.toString().padLeft(4, '0')}-'
            '${local.month.toString().padLeft(2, '0')}-'
            '${local.day.toString().padLeft(2, '0')} '
            '${local.hour.toString().padLeft(2, '0')}:'
            '${local.minute.toString().padLeft(2, '0')}';
      }
    }

    final DateTime utcTime = _utcFormat.parseUtc(utcTimeString).toLocal();
    return _localFormat.format(utcTime);
  }
}

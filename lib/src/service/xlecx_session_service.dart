import 'package:acervo_hc/src/service/storage_service.dart';

XlecxSessionService xlecxSessionService = XlecxSessionService();

/// Stores the Xlecx session cookie entered by the user.
///
/// Some posts on the site are restricted to registered users. The app does not
/// drive the site's login form (it sits behind Cloudflare/Turnstile), so the
/// user copies the `Cookie` header from a browser session that is already
/// logged in.
///
/// The value lives in [storageService] (GetStorage) on the device only. It is
/// as sensitive as the account password: it grants full access to the session
/// until the site expires it.
class XlecxSessionService {
  static const String _cookieKey = 'xlecxSessionCookie';

  /// The sanitized cookie header, or null when none is configured.
  String? get cookie {
    final String? value = storageService.read<String>(_cookieKey);
    if (value == null || value.trim().isEmpty) {
      return null;
    }
    return value.trim();
  }

  bool get hasCookie => cookie != null;

  /// Accepts both a bare `PHPSESSID=...` and a full `Cookie:` header pasted
  /// from the browser's devtools.
  Future<void> save(String value) async {
    final String normalized = value
        .trim()
        .replaceFirst(RegExp(r'^cookie:\s*', caseSensitive: false), '')
        .replaceAll(RegExp(r'[\r\n]+'), ' ')
        .trim();

    await storageService.write(_cookieKey, normalized);
  }

  Future<void> clear() => storageService.write(_cookieKey, '');
}

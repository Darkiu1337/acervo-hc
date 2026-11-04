import 'package:acervo_hc/src/service/storage_service.dart';

XlecxSessionService xlecxSessionService = XlecxSessionService();

/// Stores the Xlecx session cookies entered by the user.
///
/// Some posts on the site are restricted to registered users. The app does not
/// drive the site's login form (it sits behind Cloudflare/Turnstile), so the
/// user copies the cookies from a browser session that is already logged in.
///
/// DLE authenticates either through `PHPSESSID` or, when "remember me" is on,
/// through the `dle_user_id` + `dle_password` pair, so each cookie has its own
/// field (like the E-Hentai login form).
///
/// The values live in [storageService] (GetStorage) on the device only. They
/// are as sensitive as the account password: they grant full access to the
/// session until the site expires it.
class XlecxSessionService {
  static const String phpsessidCookieName = 'PHPSESSID';
  static const String userIdCookieName = 'dle_user_id';
  static const String passwordCookieName = 'dle_password';

  static const String _phpsessidKey = 'xlecxCookiePHPSESSID';
  static const String _userIdKey = 'xlecxCookieDleUserId';
  static const String _passwordKey = 'xlecxCookieDlePassword';

  /// Single-string storage from the first build, migrated into the fields.
  static const String _legacyKey = 'xlecxSessionCookie';

  bool _migrated = false;

  String? get phpsessid {
    _migrate();
    return _read(_phpsessidKey);
  }

  String? get dleUserId {
    _migrate();
    return _read(_userIdKey);
  }

  String? get dlePassword {
    _migrate();
    return _read(_passwordKey);
  }

  bool get hasCookie => phpsessid != null || dleUserId != null || dlePassword != null;

  /// The `Cookie` header sent on every request, or null when nothing is set.
  String? get cookie {
    final List<String> parts = <String>[];

    void add(String name, String? value) {
      if (value != null && value.isNotEmpty) {
        parts.add('$name=$value');
      }
    }

    add(phpsessidCookieName, phpsessid);
    add(userIdCookieName, dleUserId);
    add(passwordCookieName, dlePassword);

    return parts.isEmpty ? null : parts.join('; ');
  }

  Future<void> save({
    required String phpsessid,
    required String dleUserId,
    required String dlePassword,
  }) async {
    _migrated = true;
    await storageService.write(_phpsessidKey, phpsessid.trim());
    await storageService.write(_userIdKey, dleUserId.trim());
    await storageService.write(_passwordKey, dlePassword.trim());
  }

  Future<void> clear() async {
    _migrated = true;
    await storageService.write(_phpsessidKey, '');
    await storageService.write(_userIdKey, '');
    await storageService.write(_passwordKey, '');
    await storageService.write(_legacyKey, '');
  }

  String? _read(String key) {
    final String? value = storageService.read<String>(key);
    if (value == null || value.trim().isEmpty) {
      return null;
    }
    return value.trim();
  }

  /// Splits the old single-string value into the three fields, once.
  void _migrate() {
    if (_migrated) {
      return;
    }
    _migrated = true;

    final String? legacy = storageService.read<String>(_legacyKey);
    if (legacy == null || legacy.trim().isEmpty) {
      return;
    }

    for (final String pair in legacy.split(';')) {
      final int separator = pair.indexOf('=');
      if (separator <= 0) {
        continue;
      }

      final String name = pair.substring(0, separator).trim().toLowerCase();
      final String value = pair.substring(separator + 1).trim();
      if (value.isEmpty) {
        continue;
      }

      if (name == phpsessidCookieName.toLowerCase()) {
        storageService.write(_phpsessidKey, value);
      } else if (name == userIdCookieName) {
        storageService.write(_userIdKey, value);
      } else if (name == passwordCookieName) {
        storageService.write(_passwordKey, value);
      }
    }

    storageService.write(_legacyKey, '');
  }
}

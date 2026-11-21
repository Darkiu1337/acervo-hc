import 'package:acervo_hc/src/utils/xlecx_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('XlecxParser login helpers', () {
    test('detects guest vs logged-in HTML headers', () {
      const String guestHtml = '<button class="header__login js-show-login">Authorization</button>';
      const String loggedHtml =
          '<button class="header__login header__login-btn--logged">Profile</button>'
          '<a href="https://xlecx.one/user/Darkiu%20Test/">Profile</a>';

      expect(XlecxParser.isGuestHtml(guestHtml), isTrue);
      expect(XlecxParser.isLoggedInHtml(guestHtml), isFalse);
      expect(XlecxParser.parseLoggedInUsername(guestHtml), isNull);

      expect(XlecxParser.isLoggedInHtml(loggedHtml), isTrue);
      expect(XlecxParser.parseLoggedInUsername(loggedHtml), 'Darkiu Test');
    });

    test('extracts DLE authorization error banner', () {
      const String errorHtml = '''
        <div class="message-info">
          <div class="message-info__title">Authorization error</div>
          <div class="message-info__content">Warning! Failed to login. You may have entered an incorrect username or password.</div>
        </div>
      ''';

      expect(
        XlecxParser.parseLoginError(errorHtml),
        'Warning! Failed to login. You may have entered an incorrect username or password.',
      );
    });

    test('returns null when no login error banner is present', () {
      const String okHtml = '<div class="header__login-btn--logged">OK</div>';
      expect(XlecxParser.parseLoginError(okHtml), isNull);
    });
  });
}

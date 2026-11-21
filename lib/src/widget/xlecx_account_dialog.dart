import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:acervo_hc/src/network/xlecx_request.dart';
import 'package:acervo_hc/src/service/xlecx_session_service.dart';
import 'package:acervo_hc/src/utils/toast_util.dart';
import 'package:acervo_hc/src/widget/xlecx_mark.dart';

/// Opens the Xlecx account panel and returns true when the session changed
/// (logged in, saved cookies, or signed out) so the caller can reload.
Future<bool> showXlecxAccountDialog(BuildContext context) async {
  final bool? changed = await showDialog<bool>(
    context: context,
    builder: (_) => const XlecxAccountDialog(),
  );

  return changed ?? false;
}

enum _XlecxAuthMode { credentials, cookies }

/// Lets the user sign into xlecx.one directly with username/email and password,
/// with an optional manual-cookie fallback (for Google OAuth accounts or when
/// Cloudflare challenges the login form).
class XlecxAccountDialog extends StatefulWidget {
  const XlecxAccountDialog({Key? key}) : super(key: key);

  @override
  State<XlecxAccountDialog> createState() => _XlecxAccountDialogState();
}

class _XlecxAccountDialogState extends State<XlecxAccountDialog> {
  late final TextEditingController usernameController =
      TextEditingController(text: xlecxSessionService.username ?? '');
  final TextEditingController loginPasswordController = TextEditingController();

  late final TextEditingController phpsessidController =
      TextEditingController(text: xlecxSessionService.phpsessid ?? '');
  late final TextEditingController userIdController =
      TextEditingController(text: xlecxSessionService.dleUserId ?? '');
  late final TextEditingController cookiePasswordController =
      TextEditingController(text: xlecxSessionService.dlePassword ?? '');

  _XlecxAuthMode mode = _XlecxAuthMode.credentials;
  bool obscurePassword = true;
  bool busy = false;
  bool sessionChanged = false;
  String? errorMessage;

  @override
  void dispose() {
    usernameController.dispose();
    loginPasswordController.dispose();
    phpsessidController.dispose();
    userIdController.dispose();
    cookiePasswordController.dispose();
    super.dispose();
  }

  Future<void> _loginWithCredentials() async {
    if (busy) {
      return;
    }

    final String username = usernameController.text.trim();
    final String password = loginPasswordController.text;
    if (username.isEmpty || password.isEmpty) {
      setState(() => errorMessage = 'xlecxCredentialsEmpty'.tr);
      return;
    }

    setState(() {
      busy = true;
      errorMessage = null;
    });

    final XlecxLoginResult result = await xlecxRequest.login(
      username: username,
      password: password,
    );

    if (!mounted) {
      return;
    }

    if (result.success) {
      toast('xlecxLoginSuccess'.tr);
      Navigator.of(context).pop(true);
      return;
    }

    setState(() {
      busy = false;
      errorMessage = result.isCloudflareBlocked
          ? 'xlecxBlocked'.tr
          : (result.errorMessage != null && result.errorMessage!.isNotEmpty)
              ? result.errorMessage
              : 'xlecxLoginFailed'.tr;
    });
  }

  Future<bool> _persistCookies() async {
    final bool isEmpty = phpsessidController.text.trim().isEmpty &&
        userIdController.text.trim().isEmpty &&
        cookiePasswordController.text.trim().isEmpty;
    if (isEmpty) {
      toast('xlecxCookieEmpty'.tr);
      return false;
    }

    await xlecxSessionService.save(
      phpsessid: phpsessidController.text,
      dleUserId: userIdController.text,
      dlePassword: cookiePasswordController.text,
    );
    return true;
  }

  Future<void> _saveCookies() async {
    if (busy || !await _persistCookies()) {
      return;
    }

    if (mounted) {
      Navigator.of(context).pop(true);
    }
  }

  Future<void> _logout() async {
    if (busy) {
      return;
    }
    await xlecxSessionService.clear();
    if (!mounted) {
      return;
    }

    loginPasswordController.clear();
    phpsessidController.clear();
    userIdController.clear();
    cookiePasswordController.clear();
    setState(() {
      sessionChanged = true;
      errorMessage = null;
    });
    toast('xlecxLogoutSuccess'.tr);
  }

  Future<void> _verify() async {
    if (busy) {
      return;
    }
    if (mode == _XlecxAuthMode.cookies && !await _persistCookies()) {
      return;
    }

    setState(() {
      busy = true;
      errorMessage = null;
    });

    final bool? result = await xlecxRequest.verifySession();
    if (!mounted) {
      return;
    }
    setState(() => busy = false);

    toast(
      switch (result) {
        true => 'xlecxVerifyOk'.tr,
        false => 'xlecxVerifyRestricted'.tr,
        _ => 'xlecxVerifyUnknown'.tr,
      },
      isShort: false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool hasSession = xlecxSessionService.hasCookie;
    final String? currentUsername = xlecxSessionService.username;
    final ColorScheme colors = Theme.of(context).colorScheme;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (!didPop) {
          Navigator.of(context).pop(sessionChanged);
        }
      },
      child: AlertDialog(
        title: Row(
          children: [
            const XlecxMark(size: 20),
            const SizedBox(width: 8),
            Expanded(child: Text('xlecxAccount'.tr)),
          ],
        ),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (hasSession) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: colors.primaryContainer.withValues(alpha: 0.45),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.check_circle, size: 18, color: colors.primary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            currentUsername != null && currentUsername.isNotEmpty
                                ? '${'xlecxConnectedAs'.tr}: $currentUsername'
                                : 'xlecxSessionActive'.tr,
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: colors.onSurface),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<_XlecxAuthMode>(
                    segments: <ButtonSegment<_XlecxAuthMode>>[
                      ButtonSegment<_XlecxAuthMode>(
                        value: _XlecxAuthMode.credentials,
                        icon: const Icon(Icons.login, size: 16),
                        label: Text('xlecxLoginTab'.tr),
                      ),
                      ButtonSegment<_XlecxAuthMode>(
                        value: _XlecxAuthMode.cookies,
                        icon: const Icon(Icons.cookie_outlined, size: 16),
                        label: Text('xlecxCookiesTab'.tr),
                      ),
                    ],
                    selected: <_XlecxAuthMode>{mode},
                    onSelectionChanged: busy
                        ? null
                        : (Set<_XlecxAuthMode> selection) {
                            setState(() {
                              mode = selection.first;
                              errorMessage = null;
                            });
                          },
                  ),
                ),
                const SizedBox(height: 12),
                if (mode == _XlecxAuthMode.credentials) ...[
                  Text(
                    'xlecxLoginHint'.tr,
                    style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: usernameController,
                    autofocus: !hasSession,
                    enabled: !busy,
                    textInputAction: TextInputAction.next,
                    autofillHints: const <String>[AutofillHints.username, AutofillHints.email],
                    decoration: InputDecoration(
                      isDense: true,
                      labelText: 'xlecxUsernameLabel'.tr,
                      prefixIcon: const Icon(Icons.person_outline, size: 18),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: loginPasswordController,
                    enabled: !busy,
                    obscureText: obscurePassword,
                    textInputAction: TextInputAction.done,
                    autofillHints: const <String>[AutofillHints.password],
                    onSubmitted: (_) => _loginWithCredentials(),
                    decoration: InputDecoration(
                      isDense: true,
                      labelText: 'password'.tr,
                      prefixIcon: const Icon(Icons.lock_outline, size: 18),
                      suffixIcon: IconButton(
                        icon: Icon(obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined, size: 18),
                        onPressed: () => setState(() => obscurePassword = !obscurePassword),
                      ),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ] else ...[
                  Text(
                    'xlecxAccountHint'.tr,
                    style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
                  ),
                  const SizedBox(height: 12),
                  _cookieField(phpsessidController, XlecxSessionService.phpsessidCookieName),
                  const SizedBox(height: 8),
                  _cookieField(userIdController, XlecxSessionService.userIdCookieName),
                  const SizedBox(height: 8),
                  _cookieField(cookiePasswordController, XlecxSessionService.passwordCookieName),
                ],
                if (errorMessage != null) ...[
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: colors.errorContainer.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      errorMessage!,
                      style: TextStyle(fontSize: 12, color: colors.onErrorContainer),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          if (hasSession)
            TextButton(
              onPressed: busy ? null : _logout,
              child: Text('xlecxAccountClear'.tr),
            ),
          if (hasSession || mode == _XlecxAuthMode.cookies)
            TextButton(
              onPressed: busy ? null : _verify,
              child: Text('xlecxVerify'.tr),
            ),
          FilledButton(
            onPressed: busy
                ? null
                : (mode == _XlecxAuthMode.credentials ? _loginWithCredentials : _saveCookies),
            child: busy
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : Text(mode == _XlecxAuthMode.credentials ? 'login'.tr : 'xlecxAccountSave'.tr),
          ),
        ],
      ),
    );
  }

  Widget _cookieField(TextEditingController controller, String cookieName) {
    return TextField(
      controller: controller,
      enabled: !busy,
      style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
      decoration: InputDecoration(
        isDense: true,
        labelText: cookieName,
        prefixIcon: const Icon(Icons.cookie_outlined, size: 18),
        border: const OutlineInputBorder(),
      ),
    );
  }
}

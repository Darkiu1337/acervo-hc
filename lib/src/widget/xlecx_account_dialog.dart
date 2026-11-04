import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:acervo_hc/src/network/xlecx_request.dart';
import 'package:acervo_hc/src/service/xlecx_session_service.dart';
import 'package:acervo_hc/src/utils/toast_util.dart';
import 'package:acervo_hc/src/widget/xlecx_mark.dart';

/// Opens the Xlecx account panel and returns true when cookies were saved
/// (so the caller can reload a post that was refused).
Future<bool> showXlecxAccountDialog(BuildContext context) async {
  final bool? saved = await showDialog<bool>(
    context: context,
    builder: (_) => const XlecxAccountDialog(),
  );

  return saved ?? false;
}

/// Lets the user paste the session cookies of a logged-in xlecx.one account.
///
/// The site restricts some posts to registered users and its login form is
/// behind Cloudflare, so the app does not ask for the password: the user copies
/// the cookies from the browser and they are sent on every request. One field
/// per cookie, like the E-Hentai login form.
class XlecxAccountDialog extends StatefulWidget {
  const XlecxAccountDialog({Key? key}) : super(key: key);

  @override
  State<XlecxAccountDialog> createState() => _XlecxAccountDialogState();
}

class _XlecxAccountDialogState extends State<XlecxAccountDialog> {
  late final TextEditingController phpsessidController =
      TextEditingController(text: xlecxSessionService.phpsessid ?? '');
  late final TextEditingController userIdController =
      TextEditingController(text: xlecxSessionService.dleUserId ?? '');
  late final TextEditingController passwordController =
      TextEditingController(text: xlecxSessionService.dlePassword ?? '');

  bool busy = false;

  @override
  void dispose() {
    phpsessidController.dispose();
    userIdController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  Future<bool> _persist() async {
    final bool isEmpty = phpsessidController.text.trim().isEmpty &&
        userIdController.text.trim().isEmpty &&
        passwordController.text.trim().isEmpty;
    if (isEmpty) {
      toast('xlecxCookieEmpty'.tr);
      return false;
    }

    await xlecxSessionService.save(
      phpsessid: phpsessidController.text,
      dleUserId: userIdController.text,
      dlePassword: passwordController.text,
    );
    return true;
  }

  Future<void> _save() async {
    if (!await _persist()) {
      return;
    }

    if (mounted) {
      Navigator.of(context).pop(true);
    }
  }

  Future<void> _clear() async {
    await xlecxSessionService.clear();
    if (!mounted) {
      return;
    }

    phpsessidController.clear();
    userIdController.clear();
    passwordController.clear();
    setState(() {});
  }

  Future<void> _verify() async {
    if (busy || !await _persist()) {
      return;
    }

    setState(() => busy = true);
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
    final bool hasCookie = xlecxSessionService.hasCookie;

    return AlertDialog(
      title: Row(
        children: [
          const XlecxMark(size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text('xlecxAccount'.tr)),
        ],
      ),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'xlecxAccountHint'.tr,
                style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 12),
              _field(phpsessidController, XlecxSessionService.phpsessidCookieName, autofocus: true),
              const SizedBox(height: 8),
              _field(userIdController, XlecxSessionService.userIdCookieName),
              const SizedBox(height: 8),
              _field(passwordController, XlecxSessionService.passwordCookieName),
            ],
          ),
        ),
      ),
      actions: [
        if (hasCookie)
          TextButton(
            onPressed: busy ? null : _clear,
            child: Text('xlecxAccountClear'.tr),
          ),
        TextButton(
          onPressed: busy ? null : _verify,
          child: busy
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : Text('xlecxVerify'.tr),
        ),
        FilledButton(
          onPressed: busy ? null : _save,
          child: Text('xlecxAccountSave'.tr),
        ),
      ],
    );
  }

  Widget _field(TextEditingController controller, String cookieName, {bool autofocus = false}) {
    return TextField(
      controller: controller,
      autofocus: autofocus,
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

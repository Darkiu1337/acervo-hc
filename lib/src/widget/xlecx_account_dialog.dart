import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:acervo_hc/src/network/xlecx_request.dart';
import 'package:acervo_hc/src/service/xlecx_session_service.dart';
import 'package:acervo_hc/src/utils/toast_util.dart';
import 'package:acervo_hc/src/widget/xlecx_mark.dart';

/// Opens the Xlecx account panel and returns true when a cookie was saved
/// (so the caller can reload a post that was refused).
Future<bool> showXlecxAccountDialog(BuildContext context) async {
  final bool? saved = await showDialog<bool>(
    context: context,
    builder: (_) => const XlecxAccountDialog(),
  );

  return saved ?? false;
}

/// Lets the user paste the session cookie of a logged-in xlecx.one account.
///
/// The site restricts some posts to registered users and its login form is
/// behind Cloudflare, so the app does not ask for the password: the user copies
/// the `Cookie` header from the browser and it is used on every request.
class XlecxAccountDialog extends StatefulWidget {
  const XlecxAccountDialog({Key? key}) : super(key: key);

  @override
  State<XlecxAccountDialog> createState() => _XlecxAccountDialogState();
}

class _XlecxAccountDialogState extends State<XlecxAccountDialog> {
  late final TextEditingController controller = TextEditingController(text: xlecxSessionService.cookie ?? '');

  bool busy = false;

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  Future<bool> _persist() async {
    final String value = controller.text.trim();
    if (value.isEmpty) {
      toast('xlecxCookieEmpty'.tr);
      return false;
    }

    await xlecxSessionService.save(value);
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

    controller.clear();
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
              TextField(
                controller: controller,
                minLines: 2,
                maxLines: 4,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                decoration: InputDecoration(
                  labelText: 'xlecxCookieLabel'.tr,
                  hintText: 'PHPSESSID=...; dle_user_id=...; dle_password=...',
                  border: const OutlineInputBorder(),
                ),
              ),
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
}

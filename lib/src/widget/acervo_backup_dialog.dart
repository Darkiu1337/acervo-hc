import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:acervo_hc/src/service/acervo_backup_service.dart';
import 'package:acervo_hc/src/utils/route_util.dart';

/// Dialog for selecting which data sections to include in a local backup export.
class AcervoBackupExportDialog extends StatefulWidget {
  const AcervoBackupExportDialog({super.key});

  @override
  State<AcervoBackupExportDialog> createState() => _AcervoBackupExportDialogState();
}

class _AcervoBackupExportDialogState extends State<AcervoBackupExportDialog> {
  final Set<AcervoBackupSection> _selected = Set<AcervoBackupSection>.from(AcervoBackupSection.values);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('selectExportItems'.tr),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  TextButton(
                    onPressed: () => setState(() => _selected.addAll(AcervoBackupSection.values)),
                    child: Text('selectAll'.tr),
                  ),
                  TextButton(
                    onPressed: () => setState(_selected.clear),
                    child: Text('clear'.tr),
                  ),
                ],
              ),
              ...AcervoBackupSection.values.map(
                (AcervoBackupSection section) => CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(section.labelKey.tr),
                  value: _selected.contains(section),
                  onChanged: (bool? checked) {
                    setState(() {
                      if (checked ?? false) {
                        _selected.add(section);
                      } else {
                        _selected.remove(section);
                      }
                    });
                  },
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: backRoute, child: Text('cancel'.tr)),
        FilledButton(
          onPressed: _selected.isEmpty ? null : () => backRoute(result: Set<AcervoBackupSection>.from(_selected)),
          child: Text('OK'.tr),
        ),
      ],
    );
  }
}

class AcervoBackupImportSelection {
  final Set<AcervoBackupSection> sections;
  final AcervoBackupImportMode mode;

  const AcervoBackupImportSelection({
    required this.sections,
    required this.mode,
  });
}

/// Dialog shown after picking a backup file so the user can inspect its
/// contents, choose sections, and pick Merge vs Replace before importing.
class AcervoBackupImportDialog extends StatefulWidget {
  final AcervoBackupDocument document;

  const AcervoBackupImportDialog({
    super.key,
    required this.document,
  });

  @override
  State<AcervoBackupImportDialog> createState() => _AcervoBackupImportDialogState();
}

class _AcervoBackupImportDialogState extends State<AcervoBackupImportDialog> {
  late final Set<AcervoBackupSection> _selected;
  AcervoBackupImportMode _mode = AcervoBackupImportMode.merge;

  @override
  void initState() {
    super.initState();
    _selected = Set<AcervoBackupSection>.from(widget.document.availableSections);
  }

  @override
  Widget build(BuildContext context) {
    final AcervoBackupDocument doc = widget.document;
    final List<AcervoBackupSection> ordered =
        AcervoBackupSection.values.where((s) => doc.availableSections.contains(s)).toList();

    final String subtitle = doc.isLegacyFormat
        ? 'backupLegacyFormat'.tr
        : [
            if (doc.appVersion != null && doc.appVersion!.isNotEmpty) 'v${doc.appVersion}',
            if (doc.exportedAt != null) DateFormat('yyyy-MM-dd HH:mm').format(doc.exportedAt!.toLocal()),
          ].join(' · ');

    return AlertDialog(
      title: Text('importData'.tr),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (subtitle.isNotEmpty) ...[
                Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 12),
              ],
              Text('backupImportMode'.tr, style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  ChoiceChip(
                    label: Text('backupModeMerge'.tr),
                    selected: _mode == AcervoBackupImportMode.merge,
                    onSelected: (_) => setState(() => _mode = AcervoBackupImportMode.merge),
                  ),
                  ChoiceChip(
                    label: Text('backupModeReplace'.tr),
                    selected: _mode == AcervoBackupImportMode.replace,
                    onSelected: (_) => setState(() => _mode = AcervoBackupImportMode.replace),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                _mode == AcervoBackupImportMode.merge ? 'backupModeMergeHint'.tr : 'backupModeReplaceHint'.tr,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 8),
              ...ordered.map((AcervoBackupSection section) {
                final int? count = doc.sectionCounts[section];
                return CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(section.labelKey.tr),
                  subtitle: count != null ? Text('$count') : null,
                  value: _selected.contains(section),
                  onChanged: (bool? checked) {
                    setState(() {
                      if (checked ?? false) {
                        _selected.add(section);
                      } else {
                        _selected.remove(section);
                      }
                    });
                  },
                );
              }),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: backRoute, child: Text('cancel'.tr)),
        FilledButton(
          onPressed: _selected.isEmpty
              ? null
              : () => backRoute(
                    result: AcervoBackupImportSelection(
                      sections: Set<AcervoBackupSection>.from(_selected),
                      mode: _mode,
                    ),
                  ),
          child: Text('import'.tr),
        ),
      ],
    );
  }
}

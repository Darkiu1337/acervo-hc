import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:acervo_hc/src/model/gallery_client_filter.dart';

/// Dialog for configuring client-side category, language, and keyword/tag
/// filters on Popular and Ranklist pages.
class EHClientFilterDialog extends StatefulWidget {
  final GalleryClientFilter initialFilter;

  const EHClientFilterDialog({
    Key? key,
    required this.initialFilter,
  }) : super(key: key);

  @override
  State<EHClientFilterDialog> createState() => _EHClientFilterDialogState();
}

class _EHClientFilterDialogState extends State<EHClientFilterDialog> {
  late TextEditingController _keywordController;
  late Set<String> _disabledCategories;
  String? _language;

  @override
  void initState() {
    super.initState();
    _keywordController = TextEditingController(text: widget.initialFilter.keyword);
    _disabledCategories = Set<String>.from(widget.initialFilter.disabledCategories);
    _language = widget.initialFilter.language;
  }

  @override
  void dispose() {
    _keywordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('clientFilter'.tr),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _keywordController,
                decoration: InputDecoration(
                  labelText: 'keywordOrTag'.tr,
                  hintText: 'clientFilterKeywordHint'.tr,
                  prefixIcon: const Icon(Icons.search, size: 20),
                  suffixIcon: _keywordController.text.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          onPressed: () {
                            _keywordController.clear();
                            setState(() {});
                          },
                        ),
                  isDense: true,
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 16),
              Text('language'.tr, style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  ChoiceChip(
                    label: Text('all'.tr),
                    selected: _language == null,
                    onSelected: (_) => setState(() => _language = null),
                  ),
                  ...GalleryClientFilter.commonLanguages.map(
                    (String lang) => ChoiceChip(
                      label: Text(lang[0].toUpperCase() + lang.substring(1)),
                      selected: _language == lang,
                      onSelected: (_) => setState(() => _language = _language == lang ? null : lang),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text('category'.tr, style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: GalleryClientFilter.allCategories.map((String cat) {
                  final bool enabled = !_disabledCategories.contains(cat);
                  return FilterChip(
                    label: Text(cat),
                    selected: enabled,
                    onSelected: (bool selected) {
                      setState(() {
                        if (selected) {
                          _disabledCategories.remove(cat);
                        } else {
                          _disabledCategories.add(cat);
                        }
                      });
                    },
                  );
                }).toList(),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(const GalleryClientFilter()),
          child: Text('reset'.tr),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('cancel'.tr),
        ),
        FilledButton(
          onPressed: () {
            Navigator.of(context).pop(
              GalleryClientFilter(
                keyword: _keywordController.text.trim(),
                disabledCategories: Set<String>.unmodifiable(_disabledCategories),
                language: _language,
              ),
            );
          },
          child: Text('OK'.tr),
        ),
      ],
    );
  }
}

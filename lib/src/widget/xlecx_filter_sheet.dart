import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:acervo_hc/src/model/xlecx_search.dart';
import 'package:acervo_hc/src/service/xlecx_catalog_service.dart';
import 'package:acervo_hc/src/setting/style_setting.dart';

/// Opens the filter panel: a dialog on desktop layouts and a bottom sheet on
/// mobile/tablet. Returns the edited config, or null when dismissed.
Future<XlecxSearchConfig?> showXlecxFilterSheet({
  required BuildContext context,
  required XlecxSearchConfig config,
}) {
  if (styleSetting.isInDesktopLayout) {
    return Get.dialog<XlecxSearchConfig>(
      Dialog(
        child: SizedBox(
          width: 560,
          height: 640,
          child: XlecxFilterSheet(config: config),
        ),
      ),
    );
  }

  return showModalBottomSheet<XlecxSearchConfig>(
    context: context,
    isScrollControlled: true,
    builder: (_) => FractionallySizedBox(
      heightFactor: 0.9,
      child: XlecxFilterSheet(config: config),
    ),
  );
}

class XlecxFilterSheet extends StatefulWidget {
  final XlecxSearchConfig config;

  const XlecxFilterSheet({
    Key? key,
    required this.config,
  }) : super(key: key);

  @override
  State<XlecxFilterSheet> createState() => _XlecxFilterSheetState();
}

class _XlecxFilterSheetState extends State<XlecxFilterSheet> {
  late final XlecxSearchConfig draft = widget.config.copy();
  final TextEditingController searchController = TextEditingController();

  String query = '';

  @override
  void initState() {
    super.initState();

    xlecxCatalogService.ensureTags().then((_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  List<XlecxTag> get filteredTags {
    final String normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) {
      return xlecxCatalogService.tags;
    }

    return xlecxCatalogService.tags
        .where((XlecxTag tag) => tag.label.toLowerCase().contains(normalized) || tag.slug.contains(normalized))
        .toList();
  }

  void toggleInclude(XlecxTag tag) {
    if (draft.includeTags.contains(tag)) {
      draft.includeTags.remove(tag);
    } else {
      draft.excludeTags.remove(tag);
      draft.includeTags.add(tag);
    }
  }

  void toggleExclude(XlecxTag tag) {
    if (draft.excludeTags.contains(tag)) {
      draft.excludeTags.remove(tag);
    } else {
      draft.includeTags.remove(tag);
      draft.excludeTags.add(tag);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildHeader(context),
        if (draft.hasKeyword) _buildKeywordHint(context),
        _buildCategories(context),
        _buildSelectedMedia(context),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: TextField(
            controller: searchController,
            decoration: InputDecoration(
              isDense: true,
              prefixIcon: const Icon(Icons.search),
              hintText: 'tagSearchHint'.tr,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onChanged: (String value) => setState(() => query = value),
          ),
        ),
        Expanded(child: _buildTagList(context)),
        _buildSort(context),
        _buildActions(context),
      ],
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
      child: Row(
        children: [
          Text('filters'.tr, style: Theme.of(context).textTheme.titleMedium),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  Widget _buildKeywordHint(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Row(
        children: [
          const Icon(Icons.info_outline, size: 16),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'xlecxSearchIgnoresFilters'.tr,
              style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategories(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('category'.tr),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final XlecxCategory category in XlecxCategory.values)
                ChoiceChip(
                  label: Text(category.label),
                  selected: draft.category == category,
                  onSelected: (_) => setState(() => draft.category = category),
                ),
            ],
          ),
        ],
      ),
    );
  }

  /// Artist/parody/group chips selected from the detail page, removable here.
  Widget _buildSelectedMedia(BuildContext context) {
    if (draft.artist == null && draft.parody == null && draft.group == null) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        children: [
          if (draft.artist != null)
            InputChip(
              avatar: const Icon(Icons.person, size: 16),
              label: Text(draft.artist!.label),
              onDeleted: () => setState(() => draft.artist = null),
            ),
          if (draft.parody != null)
            InputChip(
              avatar: const Icon(Icons.movie_outlined, size: 16),
              label: Text(draft.parody!.label),
              onDeleted: () => setState(() => draft.parody = null),
            ),
          if (draft.group != null)
            InputChip(
              avatar: const Icon(Icons.groups_outlined, size: 16),
              label: Text(draft.group!.label),
              onDeleted: () => setState(() => draft.group = null),
            ),
        ],
      ),
    );
  }

  Widget _buildTagList(BuildContext context) {
    final List<XlecxTag> tags = filteredTags;

    if (tags.isEmpty) {
      if (xlecxCatalogService.loadingTags) {
        return const Center(child: CircularProgressIndicator());
      }

      return Center(
        child: TextButton.icon(
          onPressed: () async {
            await xlecxCatalogService.ensureTags(force: true);
            if (mounted) {
              setState(() {});
            }
          },
          icon: const Icon(Icons.refresh),
          label: Text('retry'.tr),
        ),
      );
    }

    return ListView.builder(
      itemCount: tags.length,
      itemBuilder: (BuildContext context, int index) {
        final XlecxTag tag = tags[index];
        final bool included = draft.includeTags.contains(tag);
        final bool excluded = draft.excludeTags.contains(tag);

        return ListTile(
          dense: true,
          onTap: () => setState(() => toggleInclude(tag)),
          title: Text(tag.label),
          subtitle: tag.count > 0 ? Text(tag.count.toString()) : null,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: 'includeTag'.tr,
                icon: Icon(
                  included ? Icons.check_circle : Icons.check_circle_outline,
                  color: included ? Theme.of(context).colorScheme.primary : null,
                ),
                onPressed: () => setState(() => toggleInclude(tag)),
              ),
              IconButton(
                tooltip: 'excludeTag'.tr,
                icon: Icon(
                  excluded ? Icons.remove_circle : Icons.remove_circle_outline,
                  color: excluded ? Theme.of(context).colorScheme.error : null,
                ),
                onPressed: () => setState(() => toggleExclude(tag)),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSort(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: Row(
        children: [
          Expanded(child: Text('sortBy'.tr)),
          DropdownButton<XlecxSort>(
            value: draft.sort,
            items: XlecxSort.values
                .map(
                  (XlecxSort value) => DropdownMenuItem<XlecxSort>(
                    value: value,
                    child: Text(value.labelKey.tr),
                  ),
                )
                .toList(),
            onChanged: (XlecxSort? value) {
              if (value != null) {
                setState(() => draft.sort = value);
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildActions(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          TextButton(
            onPressed: () => setState(draft.reset),
            child: Text('clearFilters'.tr),
          ),
          const Spacer(),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(draft),
            child: Text('showResults'.tr),
          ),
        ],
      ),
    );
  }
}

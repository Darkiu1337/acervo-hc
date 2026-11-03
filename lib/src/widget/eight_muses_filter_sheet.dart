import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:acervo_hc/src/model/eight_muses_search.dart';
import 'package:acervo_hc/src/service/eight_muses_catalog_service.dart';
import 'package:acervo_hc/src/setting/style_setting.dart';

enum _DirectoryTab { tags, artists }

/// Opens the filter panel: a dialog on desktop layouts and a bottom sheet on
/// mobile/tablet. Returns the edited config, or null when dismissed.
Future<EightMusesSearchConfig?> showEightMusesFilterSheet({
  required BuildContext context,
  required EightMusesSearchConfig config,
}) {
  if (styleSetting.isInDesktopLayout) {
    return Get.dialog<EightMusesSearchConfig>(
      Dialog(
        child: SizedBox(
          width: 560,
          height: 640,
          child: EightMusesFilterSheet(config: config),
        ),
      ),
    );
  }

  return showModalBottomSheet<EightMusesSearchConfig>(
    context: context,
    isScrollControlled: true,
    builder: (_) => FractionallySizedBox(
      heightFactor: 0.9,
      child: EightMusesFilterSheet(config: config),
    ),
  );
}

class EightMusesFilterSheet extends StatefulWidget {
  final EightMusesSearchConfig config;

  const EightMusesFilterSheet({
    Key? key,
    required this.config,
  }) : super(key: key);

  @override
  State<EightMusesFilterSheet> createState() => _EightMusesFilterSheetState();
}

class _EightMusesFilterSheetState extends State<EightMusesFilterSheet> {
  late final EightMusesSearchConfig draft = widget.config.copy();
  final TextEditingController searchController = TextEditingController();

  _DirectoryTab tab = _DirectoryTab.tags;
  String query = '';

  @override
  void initState() {
    super.initState();

    eightMusesCatalogService.ensureTags().then((_) {
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

  bool get isTagsTab => tab == _DirectoryTab.tags;

  List<EightMusesTag> get source => isTagsTab ? eightMusesCatalogService.tags : eightMusesCatalogService.artists;

  bool get isLoading => isTagsTab ? eightMusesCatalogService.loadingTags : eightMusesCatalogService.loadingArtists;

  List<EightMusesTag> get filteredItems {
    final String normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) {
      return source;
    }

    return source
        .where((EightMusesTag item) => item.label.toLowerCase().contains(normalized) || item.slug.contains(normalized))
        .toList();
  }

  void selectTab(_DirectoryTab value) {
    if (tab == value) {
      return;
    }

    setState(() {
      tab = value;
      query = '';
      searchController.clear();
    });

    if (value == _DirectoryTab.artists) {
      eightMusesCatalogService.ensureArtists().then((_) {
        if (mounted) {
          setState(() {});
        }
      });
    }
  }

  void toggleInclude(EightMusesTag tag) {
    if (draft.includeTags.contains(tag)) {
      draft.includeTags.remove(tag);
    } else {
      draft.excludeTags.remove(tag);
      draft.includeTags.add(tag);
    }
  }

  void toggleExclude(EightMusesTag tag) {
    if (draft.excludeTags.contains(tag)) {
      draft.excludeTags.remove(tag);
    } else {
      draft.includeTags.remove(tag);
      draft.excludeTags.add(tag);
    }
  }

  void toggleArtist(EightMusesTag artist) {
    draft.artist = draft.artist == artist ? null : artist;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildHeader(context),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: SegmentedButton<_DirectoryTab>(
            segments: <ButtonSegment<_DirectoryTab>>[
              ButtonSegment<_DirectoryTab>(
                value: _DirectoryTab.tags,
                label: Text('tags'.tr),
                icon: const Icon(Icons.sell_outlined),
              ),
              ButtonSegment<_DirectoryTab>(
                value: _DirectoryTab.artists,
                label: Text('artists'.tr),
                icon: const Icon(Icons.person_outline),
              ),
            ],
            selected: <_DirectoryTab>{tab},
            showSelectedIcon: false,
            onSelectionChanged: (Set<_DirectoryTab> selection) => selectTab(selection.first),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: TextField(
            controller: searchController,
            decoration: InputDecoration(
              isDense: true,
              prefixIcon: const Icon(Icons.search),
              hintText: isTagsTab ? 'tagSearchHint'.tr : 'artistSearchHint'.tr,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onChanged: (String value) => setState(() => query = value),
          ),
        ),
        Expanded(child: _buildList(context)),
        _buildSort(context),
        if (draft.isLocalFilterMode)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'tagModeHint'.tr,
                style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ),
          ),
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

  Widget _buildList(BuildContext context) {
    if (source.isEmpty) {
      if (isLoading) {
        return const Center(child: CircularProgressIndicator());
      }

      return Center(
        child: TextButton.icon(
          onPressed: () async {
            await (isTagsTab ? eightMusesCatalogService.ensureTags(force: true) : eightMusesCatalogService.ensureArtists(force: true));
            if (mounted) {
              setState(() {});
            }
          },
          icon: const Icon(Icons.refresh),
          label: Text('retry'.tr),
        ),
      );
    }

    final List<EightMusesTag> items = filteredItems;
    if (items.isEmpty) {
      return Center(child: Text('noData'.tr));
    }

    return ListView.builder(
      itemCount: items.length,
      itemBuilder: (BuildContext context, int index) {
        final EightMusesTag item = items[index];

        if (isTagsTab) {
          final bool included = draft.includeTags.contains(item);
          final bool excluded = draft.excludeTags.contains(item);

          return ListTile(
            dense: true,
            onTap: () => setState(() => toggleInclude(item)),
            title: Text(item.label),
            subtitle: item.count > 0 ? Text(item.count.toString()) : null,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: 'includeTag'.tr,
                  icon: Icon(
                    included ? Icons.check_circle : Icons.check_circle_outline,
                    color: included ? Theme.of(context).colorScheme.primary : null,
                  ),
                  onPressed: () => setState(() => toggleInclude(item)),
                ),
                IconButton(
                  tooltip: 'excludeTag'.tr,
                  icon: Icon(
                    excluded ? Icons.remove_circle : Icons.remove_circle_outline,
                    color: excluded ? Theme.of(context).colorScheme.error : null,
                  ),
                  onPressed: () => setState(() => toggleExclude(item)),
                ),
              ],
            ),
          );
        }

        final bool selected = draft.artist == item;

        return ListTile(
          dense: true,
          onTap: () => setState(() => toggleArtist(item)),
          title: Text(item.label),
          subtitle: item.count > 0 ? Text(item.count.toString()) : null,
          trailing: Icon(
            selected ? Icons.check_circle : Icons.radio_button_unchecked,
            color: selected ? Theme.of(context).colorScheme.primary : null,
          ),
        );
      },
    );
  }

  Widget _buildSort(BuildContext context) {
    return IgnorePointer(
      ignoring: draft.isLocalFilterMode,
      child: Opacity(
        opacity: draft.isLocalFilterMode ? 0.5 : 1,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
          child: Row(
            children: [
              Expanded(child: Text('sortBy'.tr)),
              DropdownButton<EightMusesSort>(
                value: draft.sort,
                items: EightMusesSort.values
                    .map(
                      (EightMusesSort value) => DropdownMenuItem<EightMusesSort>(
                        value: value,
                        child: Text(value.labelKey.tr),
                      ),
                    )
                    .toList(),
                onChanged: (EightMusesSort? value) {
                  if (value != null) {
                    setState(() => draft.sort = value);
                  }
                },
              ),
            ],
          ),
        ),
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

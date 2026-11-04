import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:acervo_hc/src/model/xlecx_search.dart';
import 'package:acervo_hc/src/pages/xlecx/xlecx_logic.dart';

/// Inline search bar of the Xlecx page: keyword field, filter button and the
/// active filter chips, with the site's five listings as chips.
class XlecxSearchBar extends StatelessWidget {
  final XlecxLogic logic;
  final VoidCallback onOpenFilters;

  const XlecxSearchBar({
    Key? key,
    required this.logic,
    required this.onOpenFilters,
  }) : super(key: key);

  /// Listings shown as chips, in the site's navigation order.
  static const List<XlecxSort> listings = <XlecxSort>[
    XlecxSort.newest,
    XlecxSort.recentlyUpdated,
    XlecxSort.topRated,
    XlecxSort.mostViewed,
    XlecxSort.mostCommented,
  ];

  @override
  Widget build(BuildContext context) {
    return GetBuilder<XlecxLogic>(
      id: logic.searchBarId,
      builder: (_) {
        final XlecxSearchConfig config = logic.state.config;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildField(context),
            if (config.activeFilterCount > 0) _buildChips(context, config),
            if (!config.hasKeyword && !config.hasMediaFilters) _buildListingChips(context),
            const Divider(height: 1),
          ],
        );
      },
    );
  }

  Widget _buildField(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 8),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: logic.state.searchController,
              focusNode: logic.state.searchFocusNode,
              textInputAction: TextInputAction.search,
              onSubmitted: logic.submitKeyword,
              decoration: InputDecoration(
                isDense: true,
                hintText: 'xlecxSearchHint'.tr,
                prefixIcon: const Icon(Icons.search),
                suffixIcon: ValueListenableBuilder<TextEditingValue>(
                  valueListenable: logic.state.searchController,
                  builder: (_, TextEditingValue value, __) => value.text.isEmpty
                      ? const SizedBox.shrink()
                      : IconButton(
                          icon: const Icon(Icons.close, size: 18),
                          onPressed: logic.clearKeyword,
                        ),
                ),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
          const SizedBox(width: 8),
          _buildFilterButton(context),
        ],
      ),
    );
  }

  Widget _buildFilterButton(BuildContext context) {
    final int count = logic.state.config.activeFilterCount;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        IconButton(
          tooltip: 'filters'.tr,
          icon: const Icon(Icons.tune),
          onPressed: onOpenFilters,
        ),
        if (count > 0)
          Positioned(
            right: 2,
            top: 2,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                count.toString(),
                style: TextStyle(fontSize: 10, color: Theme.of(context).colorScheme.onPrimary),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildChips(BuildContext context, XlecxSearchConfig config) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          if (config.category != XlecxCategory.all)
            _padding(
              InputChip(
                avatar: const Icon(Icons.category_outlined, size: 16),
                label: Text(config.category.label),
                onDeleted: () => logic.setCategory(XlecxCategory.all),
                deleteIcon: const Icon(Icons.close, size: 16),
              ),
            ),
          for (final XlecxTag tag in config.includeTags)
            _padding(
              InputChip(
                label: Text(tag.label),
                avatar: const Icon(Icons.check, size: 16),
                onDeleted: () => logic.toggleIncludeTag(tag),
                deleteIcon: const Icon(Icons.close, size: 16),
              ),
            ),
          for (final XlecxTag tag in config.excludeTags)
            _padding(
              InputChip(
                label: Text('- ${tag.label}'),
                backgroundColor: Theme.of(context).colorScheme.errorContainer,
                onDeleted: () => logic.toggleExcludeTag(tag),
                deleteIcon: const Icon(Icons.close, size: 16),
              ),
            ),
          if (config.artist != null)
            _padding(
              InputChip(
                avatar: const Icon(Icons.person, size: 16),
                label: Text(config.artist!.label),
                onDeleted: () => logic.selectArtist(null),
                deleteIcon: const Icon(Icons.close, size: 16),
              ),
            ),
          if (config.parody != null)
            _padding(
              InputChip(
                avatar: const Icon(Icons.movie_outlined, size: 16),
                label: Text(config.parody!.label),
                onDeleted: () => logic.selectParody(null),
                deleteIcon: const Icon(Icons.close, size: 16),
              ),
            ),
          if (config.group != null)
            _padding(
              InputChip(
                avatar: const Icon(Icons.groups_outlined, size: 16),
                label: Text(config.group!.label),
                onDeleted: () => logic.selectGroup(null),
                deleteIcon: const Icon(Icons.close, size: 16),
              ),
            ),
          TextButton(
            onPressed: logic.clearFilters,
            child: Text('clearFilters'.tr),
          ),
        ],
      ),
    );
  }

  Widget _padding(Widget child) => Padding(padding: const EdgeInsets.only(right: 6), child: child);

  Widget _buildListingChips(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        children: [
          for (final XlecxSort sort in listings) _listingChip(sort),
        ],
      ),
    );
  }

  Widget _listingChip(XlecxSort sort) {
    return ChoiceChip(
      label: Text(sort.labelKey.tr),
      selected: logic.state.config.sort == sort,
      onSelected: (_) => logic.changeListing(sort),
    );
  }
}

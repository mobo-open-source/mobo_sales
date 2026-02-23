class FilterConfig {
  final Map<String, String> filterOptions;
  final bool Function(String, Set<String>)? isFilterDisabled;
  final bool hasDateFilter;
  final List<String>? categories;
  final bool hasProductFilters;

  const FilterConfig({
    required this.filterOptions,
    this.isFilterDisabled,
    this.hasDateFilter = false,
    this.categories,
    this.hasProductFilters = false,
  });
}

class GroupByConfig {
  final Map<String, String> groupByOptions;
  final String groupByLabel;
  final Future<void> Function()? fetchGroupByOptions;

  const GroupByConfig({
    required this.groupByOptions,
    required this.groupByLabel,
    this.fetchGroupByOptions,
  });
}

class FilterAndGroupByCallbacks {
  final Future<void> Function() onClearAll;
  final Future<void> Function(Map<String, dynamic> state) onApply;
  final Future<void> Function()? onRetryCategories;

  const FilterAndGroupByCallbacks({
    required this.onClearAll,
    required this.onApply,
    this.onRetryCategories,
  });
}

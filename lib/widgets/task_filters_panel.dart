import 'package:flutter/material.dart';

const String kTaskFilterArial = 'Arial';

class TaskQuickFilter {
  final String label;
  final String value;

  const TaskQuickFilter({
    required this.label,
    required this.value,
  });
}

class TaskFilterDropdownData {
  final String label;
  final String value;
  final List<DropdownMenuItem<String>> items;
  final ValueChanged<String?> onChanged;

  const TaskFilterDropdownData({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });
}

class TaskFiltersPanel extends StatefulWidget {
  final TextEditingController searchController;
  final ValueChanged<String> onSearchChanged;
  final String searchHint;
  final List<TaskQuickFilter> quickFilters;
  final String selectedQuickFilter;
  final ValueChanged<String> onQuickFilterChanged;
  final String quickFiltersLabel;
  final List<TaskFilterDropdownData> dropdowns;
  final List<Widget> trailingFilters;
  final VoidCallback onClearFilters;
  final bool hasActiveFilters;

  const TaskFiltersPanel({
    super.key,
    required this.searchController,
    required this.onSearchChanged,
    required this.searchHint,
    required this.quickFilters,
    required this.selectedQuickFilter,
    required this.onQuickFilterChanged,
    this.quickFiltersLabel = 'Estado',
    this.dropdowns = const [],
    this.trailingFilters = const [],
    required this.onClearFilters,
    required this.hasActiveFilters,
  });

  @override
  State<TaskFiltersPanel> createState() => _TaskFiltersPanelState();
}

class _TaskFiltersPanelState extends State<TaskFiltersPanel> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isWide = MediaQuery.of(context).size.width >= 900;
    final showAdvanced =
        isWide || _expanded || (widget.dropdowns.isEmpty && widget.trailingFilters.isEmpty);

    return Container(
      width: double.infinity,
      margin: EdgeInsets.fromLTRB(isWide ? 20 : 12, 10, isWide ? 20 : 12, 8),
      padding: EdgeInsets.all(isWide ? 16 : 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(isWide ? 18 : 16),
        border: Border.all(color: scheme.outlineVariant.withOpacity(0.7)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: isWide ? 16 : 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: widget.searchController,
            decoration: InputDecoration(
              hintText: widget.searchHint,
              prefixIcon: Icon(Icons.search_rounded, color: scheme.primary),
              suffixIcon: widget.searchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear_rounded, size: 18),
                      onPressed: () {
                        widget.searchController.clear();
                        widget.onSearchChanged('');
                        setState(() {});
                      },
                    )
                  : null,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
              filled: true,
              fillColor: scheme.surfaceVariant.withOpacity(0.28),
              contentPadding: EdgeInsets.symmetric(
                horizontal: 14,
                vertical: isWide ? 12 : 10,
              ),
            ),
            onChanged: (value) {
              widget.onSearchChanged(value);
              setState(() {});
            },
          ),
          SizedBox(height: isWide ? 16 : 12),
          Text(
            widget.quickFiltersLabel.toUpperCase(),
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w900,
              color: scheme.primary,
              letterSpacing: 1.4,
              fontFamily: kTaskFilterArial,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: widget.quickFilters
                .map(
                  (filter) => _TaskQuickFilterChip(
                    label: filter.label,
                    selected: widget.selectedQuickFilter == filter.value,
                    color: scheme.primary,
                    onTap: () => widget.onQuickFilterChanged(filter.value),
                  ),
                )
                .toList(),
          ),
          if (!isWide && (widget.dropdowns.isNotEmpty || widget.trailingFilters.isNotEmpty)) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                TextButton.icon(
                  onPressed: () => setState(() => _expanded = !_expanded),
                  icon: Icon(
                    _expanded
                        ? Icons.expand_less_rounded
                        : Icons.tune_rounded,
                    size: 18,
                  ),
                  label: Text(_expanded ? 'Ocultar filtros' : 'Más filtros'),
                ),
                const Spacer(),
                if (widget.hasActiveFilters)
                  TextButton(
                    onPressed: widget.onClearFilters,
                    child: const Text('Limpiar'),
                  ),
              ],
            ),
          ],
          if ((widget.dropdowns.isNotEmpty || widget.trailingFilters.isNotEmpty) &&
              showAdvanced) ...[
            SizedBox(height: isWide ? 16 : 10),
            isWide
                ? Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      ...widget.dropdowns.map(
                        (dropdown) => SizedBox(
                          width: 220,
                          child: DropdownButtonFormField<String>(
                            value: dropdown.value,
                            items: dropdown.items,
                            decoration: InputDecoration(
                              labelText: dropdown.label,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                            ),
                            onChanged: dropdown.onChanged,
                          ),
                        ),
                      ),
                      ...widget.trailingFilters,
                    ],
                  )
                : Column(
                    children: [
                      ...widget.dropdowns.map(
                        (dropdown) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: DropdownButtonFormField<String>(
                            value: dropdown.value,
                            items: dropdown.items,
                            decoration: InputDecoration(
                              labelText: dropdown.label,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                            ),
                            onChanged: dropdown.onChanged,
                          ),
                        ),
                      ),
                      ...widget.trailingFilters.map(
                        (widget) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: SizedBox(width: double.infinity, child: widget),
                        ),
                      ),
                    ],
                  ),
          ],
          if (isWide) ...[
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                icon: const Icon(Icons.clear_all_rounded),
                label: const Text(
                  'LIMPIAR FILTROS',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 12,
                    letterSpacing: 1,
                    fontFamily: kTaskFilterArial,
                  ),
                ),
                style: TextButton.styleFrom(
                  foregroundColor: widget.hasActiveFilters
                      ? Colors.red.shade700
                      : Colors.grey.shade500,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: widget.onClearFilters,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _TaskQuickFilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  const _TaskQuickFilterChip({
    required this.label,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? color.withOpacity(0.12) : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? color.withOpacity(0.35) : const Color(0xFFE2E8F0),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: kTaskFilterArial,
            fontSize: 12,
            fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
            color: selected ? color : const Color(0xFF475569),
          ),
        ),
      ),
    );
  }
}

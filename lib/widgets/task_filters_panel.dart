import 'package:flutter/material.dart';

const String kTaskFilterArial = 'Arial';

class TaskQuickFilter {
  final String label;
  final String value;

  const TaskQuickFilter({required this.label, required this.value});
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

  bool get _hasAdvanced =>
      widget.dropdowns.isNotEmpty || widget.trailingFilters.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isWide = MediaQuery.of(context).size.width >= 900;

    return isWide ? _buildWidePanel(scheme) : _buildCompactPanel(scheme);
  }

  Widget _buildWidePanel(ColorScheme scheme) {
    final screenWidth = MediaQuery.of(context).size.width;
    final searchWidth = screenWidth >= 1180 ? 420.0 : 340.0;

    return _panelShell(
      isWide: true,
      scheme: scheme,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: searchWidth,
                child: _buildSearchField(scheme, compact: true),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _buildQuickFiltersLabel(scheme),
                    ..._buildQuickFilterChips(scheme),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              _buildClearFiltersButton(compact: true),
            ],
          ),
          if (_hasAdvanced) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                ...widget.dropdowns.map(
                  (dropdown) =>
                      SizedBox(width: 220, child: _buildDropdown(dropdown)),
                ),
                ...widget.trailingFilters,
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCompactPanel(ColorScheme scheme) {
    final showAdvanced = _expanded || !_hasAdvanced;

    return _panelShell(
      isWide: false,
      scheme: scheme,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSearchField(scheme),
          const SizedBox(height: 12),
          _buildQuickFiltersLabel(scheme),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _buildQuickFilterChips(scheme),
          ),
          if (_hasAdvanced) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                TextButton.icon(
                  onPressed: () => setState(() => _expanded = !_expanded),
                  icon: Icon(
                    _expanded ? Icons.expand_less_rounded : Icons.tune_rounded,
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
          if (_hasAdvanced && showAdvanced) ...[
            const SizedBox(height: 10),
            Column(
              children: [
                ...widget.dropdowns.map(
                  (dropdown) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _buildDropdown(dropdown),
                  ),
                ),
                ...widget.trailingFilters.map(
                  (trailingFilter) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: SizedBox(
                      width: double.infinity,
                      child: trailingFilter,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _panelShell({
    required bool isWide,
    required ColorScheme scheme,
    required Widget child,
  }) {
    final panel = Container(
      width: double.infinity,
      margin: EdgeInsets.fromLTRB(
        isWide ? 20 : 12,
        isWide ? 8 : 10,
        isWide ? 20 : 12,
        8,
      ),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(isWide ? 12 : 16),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.7)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.035),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );

    if (!isWide) return panel;

    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1180),
        child: panel,
      ),
    );
  }

  Widget _buildSearchField(ColorScheme scheme, {bool compact = false}) {
    return TextField(
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
          borderRadius: BorderRadius.circular(compact ? 10 : 14),
          borderSide: BorderSide.none,
        ),
        filled: true,
        fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.32),
        contentPadding: EdgeInsets.symmetric(
          horizontal: 14,
          vertical: compact ? 10 : 10,
        ),
      ),
      onChanged: (value) {
        widget.onSearchChanged(value);
        setState(() {});
      },
    );
  }

  Widget _buildQuickFiltersLabel(ColorScheme scheme) {
    return Padding(
      padding: const EdgeInsets.only(right: 2),
      child: Text(
        widget.quickFiltersLabel.toUpperCase(),
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w900,
          color: scheme.primary,
          letterSpacing: 1.2,
          fontFamily: kTaskFilterArial,
        ),
      ),
    );
  }

  List<Widget> _buildQuickFilterChips(ColorScheme scheme) {
    return widget.quickFilters
        .map(
          (filter) => _TaskQuickFilterChip(
            label: filter.label,
            selected: widget.selectedQuickFilter == filter.value,
            color: scheme.primary,
            onTap: () => widget.onQuickFilterChanged(filter.value),
          ),
        )
        .toList();
  }

  Widget _buildDropdown(TaskFilterDropdownData dropdown) {
    return DropdownButtonFormField<String>(
      initialValue: dropdown.value,
      items: dropdown.items,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: dropdown.label,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      onChanged: dropdown.onChanged,
    );
  }

  Widget _buildClearFiltersButton({bool compact = false}) {
    return TextButton.icon(
      icon: Icon(Icons.clear_all_rounded, size: compact ? 18 : 20),
      label: Text(
        compact ? 'Limpiar' : 'LIMPIAR FILTROS',
        style: const TextStyle(
          fontWeight: FontWeight.w900,
          fontSize: 12,
          letterSpacing: 0.8,
          fontFamily: kTaskFilterArial,
        ),
      ),
      style: TextButton.styleFrom(
        foregroundColor: widget.hasActiveFilters
            ? Colors.red.shade700
            : Colors.grey.shade500,
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 12 : 14,
          vertical: compact ? 10 : 12,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      onPressed: widget.hasActiveFilters ? widget.onClearFilters : null,
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
          color: selected
              ? color.withValues(alpha: 0.12)
              : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected
                ? color.withValues(alpha: 0.35)
                : const Color(0xFFE2E8F0),
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

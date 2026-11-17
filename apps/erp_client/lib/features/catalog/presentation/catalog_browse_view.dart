import 'package:flutter/material.dart';

import '../../../core/models/native_models.dart';
import '../../../core/ui/design.dart';
import '../../../core/ui/record_icon.dart';
import '../../../core/ui/widgets.dart';
import '../../../core/ui/workspace_ui.dart';
import 'catalog_browse_view_model.dart';

class CatalogBrowseView extends StatefulWidget {
  const CatalogBrowseView({
    super.key,
    required this.model,
    required this.onType,
    this.onReport,
  });
  final CatalogBrowseViewModel model;
  final ValueChanged<NativeType> onType;
  final ValueChanged<String>? onReport;
  bool get create => model.create;
  bool get knittingOnly => model.knittingOnly;
  @override
  State<CatalogBrowseView> createState() => _CatalogBrowseViewState();
}

class _CatalogBrowseViewState extends State<CatalogBrowseView> {
  late final _search = TextEditingController(text: widget.model.query);
  bool get _reports => widget.model.reportsSelected;
  @override
  void didUpdateWidget(covariant CatalogBrowseView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.model != widget.model) {
      _search.text = widget.model.query;
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final model = widget.model;
    final allLabel = model.knittingOnly ? 'All records' : 'All modules';
    final showReports = model.showReports;
    final modules = model.modules;
    final module = model.module;
    final query = model.query;
    final types = model.types;
    final reports = model.reports;
    final count = model.count;

    return LayoutBuilder(
      builder: (context, box) {
        final textScale = MediaQuery.textScalerOf(context).scale(14) / 14;
        final desktop = box.maxWidth >= 900 * textScale.clamp(1, 1.5);
        Widget moduleFilter() => PopupMenuButton<String>(
          tooltip: 'Filter by module',
          initialValue: module,
          onSelected: (value) =>
              setState(() => widget.model.selectModule(value)),
          itemBuilder: (_) => [
            for (final name in ['', ...modules])
              PopupMenuItem(
                value: name,
                child: Text(name.isEmpty ? allLabel : name),
              ),
          ],
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.filter_list, size: 18),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      module.isEmpty ? allLabel : module,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const Icon(Icons.arrow_drop_down),
                ],
              ),
            ),
          ),
        );

        final list = CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Wrap(
                      spacing: 16,
                      runSpacing: 8,
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (desktop)
                          Display(module.isEmpty ? allLabel : module, size: 34)
                        else
                          moduleFilter(),
                        if (showReports)
                          SegmentedButton<bool>(
                            showSelectedIcon: false,
                            style: SegmentedButton.styleFrom(
                              selectedBackgroundColor: WorkspaceTheme.charcoal,
                              selectedForegroundColor: WorkspaceTheme.light,
                            ),
                            segments: const [
                              ButtonSegment(
                                value: false,
                                icon: Icon(Icons.folder_open_outlined),
                                label: Text('Records'),
                              ),
                              ButtonSegment(
                                value: true,
                                icon: Icon(Icons.bar_chart_outlined),
                                label: Text('Reports'),
                              ),
                            ],
                            selected: {_reports},
                            onSelectionChanged: (value) => setState(
                              () => widget.model.selectReports(value.first),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _search,
                      decoration: InputDecoration(
                        hintText: _reports
                            ? 'Search reports or tasks…'
                            : 'Search records or tasks…',
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: _search.text.isEmpty
                            ? null
                            : IconButton(
                                tooltip: 'Clear search',
                                onPressed: () => setState(() {
                                  _search.clear();
                                  widget.model.search('');
                                }),
                                icon: const Icon(Icons.close),
                              ),
                      ),
                      onChanged: (value) =>
                          setState(() => widget.model.search(value)),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _reports
                          ? '$count available reports'
                          : '$count available record types',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
            if (count == 0)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(30),
                  child: Text(
                    query.isEmpty && module.isEmpty
                        ? widget.create
                              ? 'Your account has no record types available to create.'
                              : _reports
                              ? 'No reports are available to your account.'
                              : 'No record types are available to your account.'
                        : _reports
                        ? 'No matching reports.'
                        : 'No matching record types.',
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            else
              SliverList.separated(
                itemCount: count,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final type = _reports ? null : types[i];
                  final report = _reports ? reports[i] : null;
                  final name = type?.name ?? report!['name'] as String;
                  final group =
                      type?.module ?? report!['module']?.toString() ?? 'Other';
                  final symbol = recordSymbol(
                    name,
                    report: _reports,
                    settings: type?.single == true,
                    tree: type?.tree == true,
                  );
                  final generic =
                      symbol == Icons.description_outlined ||
                      symbol == Icons.bar_chart_outlined;
                  return Material(
                    color: WorkspaceTheme.surface,
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                      ),
                      minVerticalPadding: 6,
                      minTileHeight: module.isEmpty ? 60 : 50,
                      leading: generic
                          ? _CatalogInitials(name: name)
                          : RecordIcon(symbol),
                      title: Text(
                        name,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      subtitle: module.isNotEmpty && type?.single != true
                          ? null
                          : Text(
                              type?.single == true
                                  ? (module.isEmpty
                                        ? '$group · Settings'
                                        : 'Settings')
                                  : group,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                      trailing: const Icon(Icons.chevron_right, size: 18),
                      onTap: () => type == null
                          ? widget.onReport!(name)
                          : widget.onType(type),
                    ),
                  );
                },
              ),
          ],
        );
        return Padding(
          padding: EdgeInsets.all(desktop ? 24 : 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (desktop) ...[
                SizedBox(
                  width: 222,
                  child: Panel(
                    dark: true,
                    frosted: true,
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(
                          padding: EdgeInsets.fromLTRB(12, 10, 12, 12),
                          child: Display('Modules', size: 26, light: true),
                        ),
                        Expanded(
                          child: ListView(
                            children: [
                              for (final name in ['', ...modules])
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 2),
                                  child: AnimatedContainer(
                                    duration: workspaceMotion(context),
                                    curve: Curves.easeOutCubic,
                                    decoration: BoxDecoration(
                                      color: module == name
                                          ? WorkspaceTheme.palePeach
                                          : Colors.transparent,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Material(
                                      type: MaterialType.transparency,
                                      child: ListTile(
                                        dense: true,
                                        minTileHeight: 44,
                                        contentPadding:
                                            const EdgeInsets.symmetric(
                                              horizontal: 12,
                                            ),
                                        minVerticalPadding: 4,
                                        selected: module == name,
                                        textColor: WorkspaceTheme.light,
                                        selectedColor: WorkspaceTheme.ink,
                                        leading: Icon(
                                          moduleSymbol(name),
                                          size: 21,
                                          color: module == name
                                              ? WorkspaceTheme.ink
                                              : WorkspaceTheme.light,
                                        ),
                                        minLeadingWidth: 33,
                                        horizontalTitleGap: 8,
                                        title: Text(
                                          name.isEmpty ? allLabel : name,
                                        ),
                                        visualDensity: VisualDensity.standard,
                                        onTap: () => setState(
                                          () => widget.model.selectModule(name),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 22),
              ],
              Expanded(child: list),
            ],
          ),
        );
      },
    );
  }
}

/// Site-defined record types have no supplied icon. Their initials keep the
/// list aligned without filling the catalogue with identical document glyphs.
class _CatalogInitials extends StatelessWidget {
  const _CatalogInitials({required this.name});
  final String name;

  @override
  Widget build(BuildContext context) {
    final initials = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .take(2)
        .map((word) => word.characters.first.toUpperCase())
        .join();
    return ExcludeSemantics(
      child: Container(
        width: 36,
        height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: WorkspaceTheme.border),
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            initials,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 12,
              color: WorkspaceTheme.ink,
            ),
          ),
        ),
      ),
    );
  }
}

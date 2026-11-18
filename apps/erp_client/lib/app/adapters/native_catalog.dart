import 'package:flutter/material.dart';

import '../../core/models/native_models.dart';
import '../../core/ui/document_dialogs.dart';
import '../../document_editor.dart';
import '../../document_fields.dart';
import '../../erp_api.dart';
import '../../invoice_composer.dart';
import '../../invoice_hub.dart';
import '../../features/catalog/data/erp_catalog_repository.dart';
import '../../features/catalog/models/catalog_models.dart';
import '../../features/catalog/presentation/catalog_browse_view.dart';
import '../../features/catalog/presentation/catalog_browse_view_model.dart';
import '../../features/catalog/presentation/catalog_screen_view.dart';
import '../../features/catalog/presentation/catalog_view_model.dart';
import '../../features/catalog/presentation/native_records_view.dart';
import '../../features/catalog/presentation/native_records_view_model.dart';
import '../../master_import_screen.dart';
import '../../native_tree.dart';
import '../../report_screen.dart';
import '../../task_planner.dart';
import '../gates/access_gate.dart';

class NativeCatalogScreen extends StatefulWidget {
  const NativeCatalogScreen({
    super.key,
    required this.api,
    this.company,
    this.create = false,
    this.knittingOnly = false,
    this.onReconcile,
    this.onBankMatch,
  });
  final ErpApi api;
  final String? company;
  final bool create, knittingOnly;
  final VoidCallback? onReconcile, onBankMatch;
  @override
  State<NativeCatalogScreen> createState() => _NativeCatalogScreenState();
}

class _NativeCatalogScreenState extends State<NativeCatalogScreen> {
  late ErpCatalogRepository _repository;
  late CatalogViewModel _model;
  late Object _owned;
  Object? _access;
  Object get _ownership =>
      (widget.api, widget.api.baseUri, widget.api.account, widget.company);
  void _create() {
    _repository = ErpCatalogRepository(
      api: widget.api,
      company: widget.company,
    );
    _owned = _ownership;
    _access = _repository.scope;
    _model = CatalogViewModel(_repository);
  }

  @override
  void initState() {
    super.initState();
    _create();
    widget.api.addAccessListener(_accessChanged);
  }

  void _accessChanged() {
    if (!mounted) {
      return;
    }
    if (_owned != _ownership) {
      _model.dispose();
      _create();
      setState(() {});
    } else if (_access != _repository.scope) {
      _access = _repository.scope;
      setState(() {});
    }
  }

  @override
  void didUpdateWidget(covariant NativeCatalogScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.api != widget.api) {
      oldWidget.api.removeAccessListener(_accessChanged);
      widget.api.addAccessListener(_accessChanged);
    }
    if (_owned != _ownership) {
      _model.dispose();
      _create();
    }
  }

  @override
  void dispose() {
    widget.api.removeAccessListener(_accessChanged);
    _model.dispose();
    super.dispose();
  }

  void _open(NativeType type) {
    final api = widget.api, company = widget.company, create = widget.create;
    if (type.name == 'Sales Invoice' && company != null && company.isNotEmpty) {
      if (create) {
        if (type.canCreate) {
          Navigator.push<String>(
            context,
            MaterialPageRoute(
              builder: (_) => InvoiceComposer(api: api, company: company),
            ),
          );
        }
      } else {
        Navigator.push<void>(
          context,
          MaterialPageRoute(
            builder: (_) => InvoiceHub(
              api: api,
              company: company,
              canCreate: type.canCreate,
            ),
          ),
        );
      }
      return;
    }
    Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (_) => create || type.single
            ? DocumentEditor(api: api, doctype: type.name, company: company)
            : NativeRecordScreen(api: api, type: type, company: company),
      ),
    );
  }

  void _report(String name) {
    final api = widget.api, company = widget.company;
    Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (_) =>
            NativeReportScreen(api: api, name: name, company: company),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => CatalogScreenView(
    model: _model,
    create: widget.create,
    knittingOnly:
        widget.api.contextFor(widget.company ?? '')?.knittingOnly ??
        widget.knittingOnly,
    onType: _open,
    onReport: _report,
    onReconcile: widget.onReconcile,
    onBankMatch: widget.onBankMatch,
    protect: (child, reload) => AccessGate(
      key: ValueKey(_owned),
      api: widget.api,
      revalidate: reload,
      child: child,
    ),
  );
}

class NativeCatalogView extends StatefulWidget {
  const NativeCatalogView({
    super.key,
    required this.catalog,
    required this.onType,
    this.onReport,
    this.create = false,
    this.knittingOnly = false,
  });
  final NativeCatalog catalog;
  final ValueChanged<NativeType> onType;
  final ValueChanged<String>? onReport;
  final bool create, knittingOnly;
  @override
  State<NativeCatalogView> createState() => _NativeCatalogViewState();
}

class _NativeCatalogViewState extends State<NativeCatalogView> {
  late final _model = CatalogBrowseViewModel(
    CatalogSnapshot.fromNative(widget.catalog),
    create: widget.create,
    allowReports: widget.onReport != null,
    knittingOnly: widget.knittingOnly,
  );
  @override
  void didUpdateWidget(covariant NativeCatalogView oldWidget) {
    super.didUpdateWidget(oldWidget);
    _model.updateCatalog(CatalogSnapshot.fromNative(widget.catalog));
    _model.configure(
      create: widget.create,
      allowReports: widget.onReport != null,
      knittingOnly: widget.knittingOnly,
    );
  }

  @override
  Widget build(BuildContext context) => CatalogBrowseView(
    model: _model,
    onType: widget.onType,
    onReport: widget.onReport,
  );
}

class NativeRecordScreen extends StatefulWidget {
  const NativeRecordScreen({
    super.key,
    required this.api,
    required this.type,
    this.company,
  });
  final ErpApi api;
  final NativeType type;
  final String? company;
  @override
  State<NativeRecordScreen> createState() => _NativeRecordScreenState();
}

class _NativeRecordScreenState extends State<NativeRecordScreen> {
  late ErpCatalogRepository _repository;
  late NativeRecordsViewModel _model;
  late Object _owned;
  Object? _access, _groupToken;
  Route<dynamic>? _groupRoute;
  Object get _ownership => (
    widget.api,
    widget.api.baseUri,
    widget.api.account,
    widget.company,
    widget.type.name,
  );
  void _create() {
    _repository = ErpCatalogRepository(
      api: widget.api,
      company: widget.company,
    );
    _owned = _ownership;
    _access = _repository.scope;
    _model = NativeRecordsViewModel(
      _repository,
      type: widget.type,
      company: widget.company,
    );
  }

  @override
  void initState() {
    super.initState();
    _create();
    widget.api.addAccessListener(_accessChanged);
  }

  void _accessChanged() {
    if (!mounted) {
      return;
    }
    if (_owned != _ownership) {
      dismissDocumentDialog(_groupRoute);
      _model.dispose();
      _create();
      setState(() {});
    } else if (_access != _repository.scope) {
      _access = _repository.scope;
      dismissDocumentDialog(_groupRoute);
      setState(() {});
    }
  }

  @override
  void didUpdateWidget(covariant NativeRecordScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.api != widget.api) {
      oldWidget.api.removeAccessListener(_accessChanged);
      widget.api.addAccessListener(_accessChanged);
    }
    if (_owned != _ownership) {
      dismissDocumentDialog(_groupRoute);
      _model.dispose();
      _create();
    }
  }

  @override
  void dispose() {
    widget.api.removeAccessListener(_accessChanged);
    dismissDocumentDialog(_groupRoute);
    _model.dispose();
    super.dispose();
  }

  Future<void> _open(String? name) async {
    final api = widget.api, type = _model.type, company = widget.company;
    if (name == null &&
        type.name == 'Sales Invoice' &&
        company != null &&
        company.isNotEmpty) {
      if (type.canCreate) {
        await Navigator.push<String>(
          context,
          MaterialPageRoute(
            builder: (_) => InvoiceComposer(api: api, company: company),
          ),
        );
      }
      return;
    }
    await Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (_) => DocumentEditor(
          api: api,
          doctype: type.name,
          name: name,
          company: company,
        ),
      ),
    );
  }

  Future<void> _import() async {
    final api = widget.api, type = _model.type, company = widget.company;
    if (company == null) {
      return;
    }
    await Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (_) =>
            MasterImportScreen(api: api, doctype: type.name, company: company),
      ),
    );
  }

  Future<void> _tasks() async {
    final api = widget.api, company = widget.company;
    if (company == null) {
      return;
    }
    await Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (_) => TaskPlanner(api: api, company: company),
      ),
    );
  }

  Future<void> _tree() async {
    final api = widget.api, type = _model.type, company = widget.company;
    await Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (_) =>
            NativeTreeScreen(api: api, type: type, company: company),
      ),
    );
  }

  Future<String?> _chooseGroup(GroupChangeIntent intent) async {
    if (_groupToken != null) {
      return null;
    }
    final model = _model, scope = _model.scope;
    final token = Object(), ownerRoute = ModalRoute.of(context);
    var chosen = '';
    _groupToken = token;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialog) {
        final route = ModalRoute.of(dialog);
        if (identical(_groupToken, token) &&
            route != null &&
            !identical(route, ownerRoute)) {
          _groupRoute = route;
        }
        if (!mounted ||
            model != _model ||
            !model.active ||
            scope != model.scope) {
          dismissDocumentDialog(_groupRoute);
          return const SizedBox.shrink();
        }
        return StatefulBuilder(
          builder: (context, update) => AlertDialog(
            title: Text('Change group for ${intent.records.length} selected'),
            content: SingleChildScrollView(
              child: NativeScalarField(
                field: NativeField.fromJson({
                  'fieldname': 'group',
                  'label': intent.groupType,
                  'fieldtype': 'Link',
                  'options': intent.groupType,
                }),
                value: chosen,
                linkType: intent.groupType,
                editable: true,
                onLink: (_, query, _) => model.groups(query),
                onChanged: (value) =>
                    update(() => chosen = value?.toString().trim() ?? ''),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialog, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: chosen.isEmpty
                    ? null
                    : () => Navigator.pop(dialog, true),
                child: const Text('Apply group'),
              ),
            ],
          ),
        );
      },
    );
    if (identical(_groupToken, token)) {
      _groupToken = null;
      _groupRoute = null;
    }
    return confirmed == true &&
            mounted &&
            model == _model &&
            model.active &&
            scope == model.scope
        ? chosen
        : null;
  }

  @override
  Widget build(BuildContext context) => NativeRecordsView(
    model: _model,
    open: _open,
    chooseGroup: _chooseGroup,
    importCsv: _import,
    openTasks: _tasks,
    browseTree: _tree,
    protect: (child, reload) => AccessGate(
      key: ValueKey(_owned),
      api: widget.api,
      revalidate: reload,
      child: child,
    ),
  );
}

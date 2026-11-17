import '../../ui/record_icon.dart';
import '../../ui/workspace_ui.dart';

import 'dart:convert';

import 'package:flutter/material.dart';

import '../../design.dart';
import '../../core/ui/record_identity.dart';
import '../../document_activity.dart';
import '../../invoice_preview.dart';
import '../../document_fields.dart';
import '../../features/operations/presentation/document_entry_steps.dart';
import '../../document_review.dart';
import '../../document_dialogs.dart';
import '../../document_recovery.dart';
import '../../specialized_fields.dart';
import '../../file_actions.dart';
import '../../erp_api.dart';
import '../../native_models.dart';
import '../../operational_handoffs.dart';
import '../../widgets.dart';
import '../../ui/access_gate.dart';

double _qty(Object? value) => double.tryParse(value?.toString() ?? '') ?? 0;

Future<double?> _productionQuantity(
  BuildContext context,
  String action,
  double maximum,
) {
  final units = maximum == maximum.truncateToDouble()
      ? maximum.toStringAsFixed(0)
      : maximum.toString();
  var text = units;
  return showDialog<double>(
    context: context,
    builder: (dialog) => StatefulBuilder(
      builder: (context, update) {
        final quantity = double.tryParse(text);
        final valid =
            quantity != null &&
            quantity.isFinite &&
            quantity > 0 &&
            quantity <= maximum;
        return AlertDialog(
          title: Text(action),
          content: TextFormField(
            initialValue: units,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'Finished product quantity',
              helperText: 'Available: $units',
              errorText: valid ? null : 'Enter a quantity up to $units.',
            ),
            onChanged: (v) => update(() => text = v),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: valid ? () => Navigator.pop(dialog, quantity) : null,
              child: const Text('Review stock entry'),
            ),
          ],
        );
      },
    ),
  );
}

class DocumentEditor extends StatefulWidget {
  const DocumentEditor({
    super.key,
    required this.api,
    required this.doctype,
    this.name,
    this.company,
    this.initial,
    this.treeParent,
    this.transition,
    this.onCreated,
  });
  final ErpApi api;
  final String doctype;
  final String? name, company, treeParent;
  final RecordIdentityTransition? transition;
  final NativeDocument? initial;
  final ValueChanged<NativeDocument>? onCreated;
  @override
  State<DocumentEditor> createState() => _DocumentEditorState();
}

class _DocumentEditorState extends State<DocumentEditor> {
  var _form = GlobalKey<_NativeDocumentFormState>();
  final _identityKey = GlobalKey();
  DocumentOperation? _completedOperation;
  int _requestContext = 0;
  @override
  void initState() {
    super.initState();
    widget.api.addAccessListener(_accessChanged);
  }

  void _accessChanged() {
    _requestContext++;
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.api.removeAccessListener(_accessChanged);
    super.dispose();
  }

  @override
  void didUpdateWidget(DocumentEditor old) {
    super.didUpdateWidget(old);
    if (old.api != widget.api ||
        old.company != widget.company ||
        old.doctype != widget.doctype ||
        old.name != widget.name) {
      _requestContext++;
      old.api.removeAccessListener(_accessChanged);
      widget.api.addAccessListener(_accessChanged);
      _form = GlobalKey<_NativeDocumentFormState>();
      _freshAccess = false;
      _future = _load();
    }
  }

  bool _freshAccess = false;
  late Future<(NativeSchema, NativeDocument)> _future = _load();
  Future<NativeDocument> _document() {
    final current = _form.currentState?._doc ?? widget.initial;
    if (!_freshAccess && widget.initial != null) {
      return Future.value(widget.initial!);
    }
    final origin = current?.data['__native_origin'];
    if (current?.isNew == true && origin is Map) {
      return widget.api.newFromNative(
        origin['doctype'] as String,
        origin['name'] as String,
        origin['action'] as String,
        origin['modified'] as String,
        quantity: origin['quantity'] as num?,
      );
    }
    return widget.api.nativeDocument(
      widget.doctype,
      name: current == null
          ? widget.name
          : current.isNew
          ? null
          : current.data['name'] as String?,
      company: widget.company,
      treeParent: widget.treeParent,
    );
  }

  Future<(NativeSchema, NativeDocument)> _load() async {
    final transition = widget.transition;
    try {
      final results = await Future.wait([
        widget.api.nativeSchema(widget.doctype),
        _document(),
      ], eagerError: true);
      return (results[0] as NativeSchema, results[1] as NativeDocument);
    } catch (_) {
      transition?.cancel();
      rethrow;
    }
  }

  Future<NativeDocument> _write(
    NativeSchema schema,
    Map<String, dynamic> values,
    String action, {
    bool workflow = false,
  }) async {
    final api = widget.api;
    final requestContext = _requestContext;
    final company = values['company']?.toString() ?? widget.company;
    Future<NativeDocument> write(String? requestId) => workflow
        ? api.transitionNative(
            schema.doctype,
            values['name'] as String,
            action,
            modified: values['modified'] as String,
            requestId: requestId,
            company: requestId == null ? null : company,
          )
        : api.saveNative(
            schema,
            values,
            action: action,
            requestId: requestId,
            company: requestId == null ? null : company,
          );
    if (company == null ||
        !schema.operationRecoverySupported ||
        !api.supportsOperationRecovery(company)) {
      try {
        return await write(null);
      } catch (error) {
        if (error is ErpException &&
            (error.validationRejected ||
                error.staleDocument ||
                error.permissionDenied ||
                error.sessionExpired)) {
          rethrow;
        }
        throw DocumentWriteUnverified(error);
      }
    }
    final operation = DocumentOperation(
      api,
      company,
      workflow ? 'native_transition' : 'native_save',
      schema.doctype,
      values['name']?.toString(),
      action,
      isCurrent: () => mounted && requestContext == _requestContext,
    );
    final result = await operation.perform((requestId) => write(requestId));
    _completedOperation = operation;
    return result;
  }

  Future<void> _reloadLatest() async {
    _freshAccess = true;
    final revision = widget.api.accessRevision;
    final fresh = _load();
    await fresh;
    if (!mounted || revision != widget.api.accessRevision) return;
    setState(() {
      _form = GlobalKey<_NativeDocumentFormState>();
      _future = fresh;
    });
  }

  void _previewInvoice(
    Map<String, dynamic> saved, {
    bool submissionReview = false,
  }) {
    final api = widget.api;
    final company = saved['company'] as String, name = saved['name'] as String;
    final revision = submissionReview ? saved['modified'] as String : null;
    Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => InvoicePreviewScreen(
          api: api,
          company: company,
          invoice: name,
          draftRevision: revision,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AccessGate(
    api: widget.api,
    revalidate: () async {
      _freshAccess = true;
      final revision = widget.api.accessRevision;
      final fresh = _load();
      await fresh;
      if (mounted && widget.api.accessRevision == revision) {
        setState(() {
          _future = fresh;
        });
      }
    },
    child: FutureBuilder<(NativeSchema, NativeDocument)>(
      future: _future,
      builder: (context, state) {
        if (state.hasData) {
          final (schema, doc) = state.data!;
          return NativeDocumentForm(
            key: _form,
            recordHeading:
                doc.data['name'] == widget.transition?.name &&
                    widget.transition?.active == true
                ? widget.transition!.label(key: _identityKey, expanded: true)
                : null,
            identityKey: (
              widget.api.baseUri,
              widget.api.account,
              widget.company,
            ),
            scopeKey: (
              widget.api,
              widget.api.account,
              widget.company,
              widget.api.accessRevision,
              widget.api.accessReady,
            ),
            schema: schema,
            initial: doc,
            onReload: _reloadLatest,
            onResultShown: (result) async =>
                _completedOperation?.acknowledge(result),
            openFieldFile: (c, field, table, row) async {
              final name =
                  _form.currentState?._doc.data['name'] ?? doc.data['name'];
              if (name == null) {
                throw const ErpException(
                  'Save the document before opening this file.',
                );
              }
              final revision = widget.api.accessRevision;
              final file = await widget.api.fieldAttachment(
                widget.doctype,
                name.toString(),
                field,
                table: table,
                row: row,
              );
              if (c.mounted &&
                  widget.api.accessReady &&
                  widget.api.accessRevision == revision) {
                await previewFile(c, file.name, file.bytes, api: widget.api);
              }
            },
            onInvoicePreview: schema.doctype == 'Sales Invoice'
                ? _previewInvoice
                : null,
            onSubmissionPreview: schema.doctype == 'Sales Invoice'
                ? (saved) => _previewInvoice(saved, submissionReview: true)
                : null,
            onActivity: (values) => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => DocumentActivityScreen(
                  api: widget.api,
                  type: widget.doctype,
                  company: values['company']?.toString() ?? widget.company,
                  name: values['name'] as String,
                ),
              ),
            ),
            onRelated: (values, action) async {
              if (operationalActions.contains(action)) {
                final target = await openOperationalAction(
                  context,
                  widget.api,
                  action,
                  values['name'] as String,
                );
                if (target == null || !context.mounted) return;
                await Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => DocumentEditor(
                      api: widget.api,
                      doctype: target.type,
                      name: target.name,
                      initial: target.draft,
                      company: widget.company,
                    ),
                  ),
                );
                if (mounted) await _reloadLatest();
                return;
              }
              double? quantity;
              if (schema.doctype == 'Work Order' &&
                  (action == 'Transfer materials' ||
                      action == 'Record finished goods')) {
                final limit = action == 'Transfer materials'
                    ? _qty(values['qty']) -
                          _qty(values['material_transferred_for_manufacturing'])
                    : (enabled(values['skip_transfer'])
                              ? _qty(values['qty'])
                              : _qty(
                                  values['material_transferred_for_manufacturing'],
                                )) -
                          _qty(values['produced_qty']);
                quantity = await _productionQuantity(context, action, limit);
                if (quantity == null || !context.mounted) return;
              }
              final created = await widget.api.newFromNative(
                schema.doctype,
                values['name'] as String,
                action,
                values['modified'] as String,
                quantity: quantity,
              );
              if (context.mounted) {
                await Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => DocumentEditor(
                      api: widget.api,
                      doctype: created.data['doctype'] as String,
                      initial: created,
                      company: widget.company,
                    ),
                  ),
                );
                // The linked voucher may have settled or fulfilled this record.
                if (mounted) await _reloadLatest();
              }
            },
            onSave: (values, action) async {
              final saved = await _write(schema, values, action);
              if (mounted &&
                  widget.onCreated != null &&
                  !saved.isNew &&
                  (values['name'] == null || enabled(values['__islocal']))) {
                widget.onCreated!(saved);
              }
              return saved;
            },
            onPartyDefaults: schema.partyDefaults
                ? (values) => widget.api.partyDefaultsNative(schema, values)
                : null,
            onItemDefaults: schema.itemDefaults
                ? (values, field, row) =>
                      widget.api.itemDefaultsNative(schema, values, field, row)
                : null,
            onPrepare: schema.preparable
                ? (values) => widget.api.prepareNative(schema, values)
                : null,
            onLink: (type, query, field) => widget.api.searchLinks(
              type,
              query,
              parent: schema.doctype,
              field: field.name,
              contextValues: {
                for (final key in ['company', 'production_item'])
                  if ((_form.currentState?._data ?? doc.data)[key]
                      case final String value)
                    key: value,
              },
            ),
            onNewRow: (values, field) =>
                widget.api.newRowNative(schema, values, field.name),
            onTransition: (values, action) =>
                _write(schema, values, action, workflow: true),
          );
        }
        return Scaffold(
          appBar: AppBar(title: Text(widget.doctype)),
          body: state.hasError
              ? MessagePanel(
                  title: 'COULD NOT OPEN',
                  message: state.error.toString(),
                  action: () => setState(() {
                    _future = _load();
                  }),
                )
              : widget.transition?.active == true
              ? SafeArea(
                  top: false,
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1120),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (widget.company case final company?)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 4),
                                child: Text(
                                  company,
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ),
                            widget.transition!.label(
                              key: _identityKey,
                              expanded: true,
                            ),
                            const SizedBox(height: 16),
                            const LinearProgressIndicator(
                              semanticsLabel: 'Opening document',
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                )
              : const Center(child: CircularProgressIndicator()),
        );
      },
    ),
  );
}

class NativeDocumentForm extends StatefulWidget {
  const NativeDocumentForm({
    super.key,
    required this.schema,
    required this.initial,
    required this.onSave,
    this.openFieldFile,
    this.onPrepare,
    this.onPartyDefaults,
    this.onItemDefaults,
    this.onLink,
    this.onNewRow,
    this.onTransition,
    this.onActivity,
    this.onInvoicePreview,
    this.onSubmissionPreview,
    this.onRelated,
    this.onReload,
    this.scopeKey,
    this.identityKey,
    this.onResultShown,
    this.recordHeading,
  });
  final Widget? recordHeading;
  final OpenFieldFile? openFieldFile;
  final Object? scopeKey, identityKey;
  final Future<void> Function(NativeDocument result)? onResultShown;
  final Future<void> Function()? onReload;
  final Future<void> Function(Map<String, dynamic>, String)? onRelated;
  final ValueChanged<Map<String, dynamic>>? onActivity,
      onInvoicePreview,
      onSubmissionPreview;

  final NativeSchema schema;
  final NativeDocument initial;
  final Future<NativeDocument> Function(
    Map<String, dynamic> values,
    String action,
  )
  onSave;
  final Future<NativeDocument> Function(Map<String, dynamic> values)? onPrepare;
  final Future<NativeDocument> Function(
    Map<String, dynamic> values,
    String action,
  )?
  onTransition;
  final LinkLookup? onLink;
  final RowDefaults? onNewRow;
  final ItemDefaults? onItemDefaults;
  final Future<NativeDocument> Function(Map<String, dynamic>)? onPartyDefaults;
  @override
  State<NativeDocumentForm> createState() => _NativeDocumentFormState();
}

class _NativeDocumentFormState extends State<NativeDocumentForm> {
  late NativeDocument _doc = widget.initial;
  late Map<String, dynamic> _data = _doc.editCopy();
  late Map<String, dynamic> _base;

  Map<String, String> _errors = {};
  bool _busy = false, _dirty = false, _leaving = false;
  String? _error, _notice;
  bool _stale = false;
  int _revision = 0;
  final _fieldsKey = GlobalKey<DocumentFieldsState>();
  final _scroll = ScrollController();
  String? _stepKey;
  bool _fullForm = false;
  DocumentEntryStep? _validatingStep;

  List<DocumentEntryStep> get _entrySteps =>
      _doc.isNew &&
          _doc.can('create') &&
          _data['__native_origin'] == null &&
          _doc.data['docstatus'] != 2
      ? DocumentEntryStep.forDraft(widget.schema, _data)
      : const [];

  void _moveToStep(String key) {
    FocusManager.instance.primaryFocus?.unfocus();
    if (_scroll.hasClients) _scroll.jumpTo(0);
    _update(() {
      _stepKey = key;
      _validatingStep = null;
      _errors = {};
      _error = null;
    });
  }

  Map<String, String> _validateFields() {
    final errors = widget.schema.validate(_data);
    final step = _validatingStep;
    if (step != null) {
      errors.removeWhere((path, _) => !step.containsError(path));
    }
    return errors;
  }

  void _nextStep(DocumentEntryStep current, DocumentEntryStep next) {
    _validatingStep = current;
    final errors = _validateFields();
    if (errors.isEmpty) {
      _moveToStep(next.key);
      return;
    }
    _update(() {
      _errors = errors;
      _error = 'Check the marked fields before continuing.';
    });
    _revealField(errors.keys.first);
  }

  Future<void> _revealField(String path, {bool openRow = false}) async {
    final step = _fullForm
        ? null
        : _entrySteps.where((step) => step.containsError(path)).firstOrNull;
    if (step != null && step.key != _stepKey) {
      _update(() => _stepKey = step.key);
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
    }
    await _fieldsKey.currentState?.revealError(path, openRow: openRow);
  }

  DialogRoute<bool>? _reviewRoute;
  int _contextRevision = 0;
  DocumentOperation? _uncertain;
  bool _unverified = false;
  bool get _locked => _busy || _uncertain != null || _unverified;

  late final _popEntry = _DocumentPopEntry(_leave);
  ModalRoute<dynamic>? _route;

  // Publish draft and operation changes in the input callback itself. A
  // platform Back event can arrive before Flutter rebuilds the form.
  void _update(VoidCallback change) {
    setState(change);
    _popEntry.canPopNotifier.value = !_locked && !_dirty && !_leaving;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = ModalRoute.of(context);
    if (_route != next) {
      _route?.unregisterPopEntry(_popEntry);
      _route = next;
      _route?.registerPopEntry(_popEntry);
    }
  }

  @override
  void initState() {
    super.initState();
    _base = widget.initial.data;
  }

  @override
  void dispose() {
    _route?.unregisterPopEntry(_popEntry);
    _popEntry.canPopNotifier.dispose();
    dismissDocumentDialog(_reviewRoute);
    _scroll.dispose();
    super.dispose();
  }

  Future<bool?> _ask(WidgetBuilder builder) async {
    if (_reviewRoute != null) return false;
    final route = DialogRoute<bool>(context: context, builder: builder);
    _reviewRoute = route;
    final result = await Navigator.of(context).push(route);
    if (identical(_reviewRoute, route)) _reviewRoute = null;
    return result;
  }

  @override
  void didUpdateWidget(covariant NativeDocumentForm old) {
    super.didUpdateWidget(old);
    if (!identical(old.initial, widget.initial) ||
        old.scopeKey != widget.scopeKey ||
        !identical(old.schema, widget.schema)) {
      _contextRevision++;
      dismissDocumentDialog(_reviewRoute);
    }
    if (old.identityKey != widget.identityKey) {
      _stepKey = null;
      _fullForm = false;
      _validatingStep = null;
      _uncertain = null;
      _unverified = false;
      _dirty = false;
      _data = {};
      _errors = {};
      _notice = null;
    }
    if (!identical(old.initial, widget.initial)) {
      _doc = widget.initial;
      final fresh = _doc.editCopy();
      if (_dirty &&
          old.initial.data['name'] == _doc.data['name'] &&
          old.initial.data['company'] == _doc.data['company'] &&
          old.schema.doctype == widget.schema.doctype &&
          _doc.can(_doc.isNew ? 'create' : 'write') &&
          fresh['docstatus'] != 2) {
        _retainDraft(widget.schema, _base, _data, fresh);
      }
      _data = fresh;
      _base = _doc.data;
      _dirty = jsonEncode(fresh) != jsonEncode(_base);
      _errors = {};
      _stale = false;
      _error = null;
      _revision++;
      _notice = _dirty
          ? 'Access refreshed. Review your retained edits before saving.'
          : 'Access refreshed. Showing current values.';
    }
    _popEntry.canPopNotifier.value = !_locked && !_dirty && !_leaving;
  }

  // Reapply only edits still allowed by the fresh schema. A draft can contain
  // partially typed numbers, so parsing belongs to validation and save.
  void _retainDraft(
    NativeSchema schema,
    Map<String, dynamic> base,
    Map<String, dynamic> draft,
    Map<String, dynamic> fresh, {
    Map<String, dynamic> parent = const {},
  }) {
    final status = (parent.isEmpty ? fresh : parent)['docstatus'];
    for (final field in schema.visibleFields(fresh, parent: parent)) {
      final key = field.name;
      if (field.layout ||
          field.locked(fresh, parent) ||
          status == 1 && !field.allowOnSubmit ||
          !draft.containsKey(key) ||
          jsonEncode(draft[key]) == jsonEncode(base[key])) {
        continue;
      }
      if (!field.table) {
        fresh[key] = draft[key];
        continue;
      }
      final child = schema.children[field.options];
      if (child == null) continue;
      final previous = [for (final r in base[key] as List? ?? []) objectMap(r)];
      final current = [for (final r in fresh[key] as List? ?? []) objectMap(r)];
      final oldByName = {
        for (final r in previous)
          if (r['name'] != null) r['name']: r,
      };
      final currentByName = {
        for (final r in current)
          if (r['name'] != null) r['name']: r,
      };
      final rows = <Map<String, dynamic>>[];
      for (final (i, value) in (draft[key] as List? ?? []).indexed) {
        final row = objectMap(value);
        final name = row['name'];
        final old = name != null
            ? oldByName[name]
            : i < previous.length && previous[i]['name'] == null
            ? previous[i]
            : null;
        final now = name != null
            ? currentByName[name]
            : i < current.length && current[i]['name'] == null
            ? current[i]
            : null;
        if (old != null && now == null) continue;
        final target =
            now ?? {'doctype': child.doctype, '__islocal': 1, 'name': ?name};
        _retainDraft(child, old ?? {}, row, target, parent: fresh);
        rows.add(target);
      }
      fresh[key] = [
        ...rows,
        for (final row in current)
          if (row['name'] != null &&
              !oldByName.containsKey(row['name']) &&
              !rows.contains(row))
            row,
      ];
    }
  }

  Future<void> _perform(
    String action, {
    bool prepare = false,
    bool workflow = false,
    bool party = false,
  }) async {
    if (_locked || _reviewRoute != null) return;
    if ((workflow || action != 'Save' && !prepare && !party) && _dirty) {
      _update(
        () => _error = workflow
            ? 'Save your changes before applying a workflow action.'
            : 'Save your changes before ${action.toLowerCase()} so the review uses current server values.',
      );
      return;
    }
    _validatingStep = null;
    final errors = widget.schema.validate(_data);
    if (!party && errors.isNotEmpty) {
      _update(() {
        _errors = errors;
        _error = 'Check the marked fields before saving.';
      });
      _revealField(errors.keys.first);
      return;
    }
    final contextRevision = _contextRevision;
    final identity = widget.identityKey;
    final snapshot = jsonEncode(_data);
    if (action != 'Save' && !prepare && !party) {
      final route = DialogRoute<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text('$action ${widget.schema.doctype}?'),
          content: DocumentReview(
            schema: widget.schema,
            document: _doc.data,
            action: action,
            onPreviewDraft:
                action == 'Submit' &&
                    !workflow &&
                    widget.schema.doctype == 'Sales Invoice' &&
                    !_doc.isNew &&
                    _doc.can('print') &&
                    _doc.data['company'] is String &&
                    _doc.data['modified'] is String &&
                    widget.onSubmissionPreview != null
                ? () {
                    if (mounted &&
                        _contextRevision == contextRevision &&
                        ModalRoute.of(c)?.isCurrent == true) {
                      widget.onSubmissionPreview!(_doc.data);
                    }
                  }
                : null,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Keep editing'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: Text('$action document'),
            ),
          ],
        ),
      );
      _reviewRoute = route;
      final confirmed = await Navigator.of(context).push(route);
      _reviewRoute = null;
      if (confirmed != true ||
          !mounted ||
          _contextRevision != contextRevision ||
          jsonEncode(_data) != snapshot) {
        return;
      }
    }
    _update(() {
      _busy = true;
      _errors = {};
      _error = null;
      _notice = null;
    });
    try {
      final result = party
          ? await widget.onPartyDefaults!(_data)
          : prepare
          ? await widget.onPrepare!(_data)
          : workflow
          ? await widget.onTransition!(_data, action)
          : await widget.onSave(_data, action);
      if (!mounted || contextRevision != _contextRevision) return;
      _update(() {
        _doc = result;
        _stale = false;
        _data = result.editCopy();
        _revision++;
        _dirty = prepare || party;
        if (!_dirty) _base = result.data;
        _notice = party
            ? 'Party details updated'
            : prepare
            ? 'Calculations updated'
            : action == 'Save'
            ? 'Saved successfully'
            : '$action completed';
      });
      if (!prepare && !party) _announceResult(result);
    } catch (e) {
      if (mounted &&
          contextRevision != _contextRevision &&
          identity == widget.identityKey &&
          e is DocumentWriteUncertain) {
        _update(() {
          _uncertain = e.operation;
          _error = 'Access changed before the result could be confirmed. Check the original request when access is available.';
        });
      } else if (mounted && contextRevision == _contextRevision) {
        _update(() {
          _stale = e is ErpException && e.staleDocument;
          if (e is DocumentWriteUncertain) _uncertain = e.operation;
          if (e is DocumentWriteUnverified) _unverified = true;
          _error = e.toString();
        });
      }
    } finally {
      if (mounted) _update(() => _busy = false);
    }
  }

  void _announceResult(NativeDocument result, {DocumentOperation? operation}) {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || !identical(_doc, result)) return;
      if (operation != null) {
        await operation.acknowledge(result);
      } else {
        await widget.onResultShown?.call(result);
      }
    });
  }

  Future<void> _checkOutcome({bool close = false}) async {
    final operation = _uncertain;
    if (operation == null || _busy) return;
    final revision = _contextRevision;
    _update(() {
      _busy = true;
      _error = null;
    });
    try {
      final response = await operation.reconcile(close: close);
      if (!mounted ||
          revision != _contextRevision ||
          !identical(_uncertain, operation)) {
        return;
      }
      if (response['state'] == 'completed') {
        final result = operation.confirmed!;
        _update(() {
          _doc = result;
          _data = result.editCopy();
          _base = result.data;
          _revision++;
          _dirty = false;
          _uncertain = null;
          _notice = '${operation.action} confirmed';
        });
        _announceResult(result, operation: operation);
      } else if (response['state'] == 'closed') {
        _update(() {
          _uncertain = null;
          _notice = 'The unposted attempt is closed. Your retained changes can be edited and saved.';
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && revision == _contextRevision) {
            operation.acknowledge(null);
          }
        });
      } else {
        _update(
          () => _error = 'No completed result is available yet. Check again, or close the unposted attempt before editing.',
        );
      }
    } catch (error) {
      if (mounted && revision == _contextRevision) {
        _update(() => _error = error.toString());
      }
    } finally {
      if (mounted) _update(() => _busy = false);
    }
  }

  Future<void> _inspectUnverified() async {
    if (_busy || _doc.isNew || widget.onReload == null) return;
    final revision = _contextRevision;
    _update(() => _busy = true);
    try {
      await widget.onReload!();
    } catch (error) {
      if (mounted && revision == _contextRevision) {
        _update(() => _error = error.toString());
      }
    } finally {
      if (mounted) _update(() => _busy = false);
    }
  }

  Future<void> _reloadConflict() async {
    if (_locked) return;
    if (_dirty) {
      final discard = await _ask(
        (c) => AlertDialog(
          title: const Text('Reload the latest version?'),
          content: const Text(
            'Your unsaved edits will be replaced by the current server values.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Keep editing'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Discard and reload'),
            ),
          ],
        ),
      );
      if (discard != true || !mounted) return;
    }
    _update(() => _busy = true);
    try {
      await widget.onReload!();
    } catch (e) {
      if (mounted) _update(() => _error = e.toString());
    } finally {
      if (mounted) _update(() => _busy = false);
    }
  }

  Future<void> _related(String action) async {
    if (_locked) return;
    if (_dirty) {
      _update(
        () => _error = 'Save your changes before creating a related document.',
      );
      return;
    }
    _update(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onRelated!(_data, action);
    } catch (e) {
      if (mounted) _update(() => _error = e.toString());
    } finally {
      if (mounted) _update(() => _busy = false);
    }
  }

  Future<void> _leave() async {
    if (_busy || _leaving) return;
    if (_uncertain != null || _unverified) {
      final leave = await _ask(
        (dialog) => AlertDialog(
          title: const Text('Keep this operation available?'),
          content: Text(
            _unverified
                ? 'The outcome is not confirmed. Locate and inspect the current record in this workspace before creating another entry or making another change.'
                : 'Its outcome is not confirmed. The original request is saved in Pending operations for this account and company. Leaving does not post it again.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog, false),
              child: const Text('Keep checking'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialog, true),
              child: const Text('Leave and check later'),
            ),
          ],
        ),
      );
      if (leave == true && mounted) Navigator.pop(context);
      return;
    }
    if (!_dirty) {
      Navigator.pop(context);
      return;
    }
    _leaving = true;
    final discard = await _ask(
      (c) => AlertDialog(
        title: const Text('Keep your changes?'),
        content: const Text('This document has unsaved changes.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Keep editing'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Discard changes'),
          ),
        ],
      ),
    );
    _leaving = false;
    if (discard == true && mounted) {
      _update(() => _dirty = false);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.pop(context);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final steps = _entrySteps;
    final guided = !_fullForm && steps.isNotEmpty;
    final index = steps.indexWhere((step) => step.key == _stepKey);
    final current = index < 0 ? 0 : index;
    final status = _doc.data['docstatus'] ?? 0;
    final canSave =
        status != 2 && (_doc.isNew ? _doc.can('create') : _doc.can('write'));
    return Scaffold(
      appBar: AppBar(
        title: WorkspaceRouteTitle(
          _doc.isNew ? 'New ${widget.schema.doctype}' : widget.schema.doctype,
          mark: RecordHeaderMark(
            widget.schema.doctype,
            settings: widget.schema.single,
          ),
        ),
        actions: [
          if (steps.isNotEmpty)
            TextButton(
              onPressed: _locked
                  ? null
                  : () {
                      FocusManager.instance.primaryFocus?.unfocus();
                      if (_scroll.hasClients) _scroll.jumpTo(0);
                      _update(() {
                        _fullForm = !_fullForm;
                        _validatingStep = null;
                      });
                    },
              child: Text(guided ? 'Full form' : 'Guided entry'),
            ),
          if (!guided)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: FilledButton(
                onPressed: _locked || !canSave ? null : () => _perform('Save'),
                child: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: WorkspaceTheme.light,
                        ),
                      )
                    : const Text('Save'),
              ),
            ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(
              child: WorkspaceBackdrop(
                child: SingleChildScrollView(
                  controller: _scroll,
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 40),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1120),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (_data['company'] is String &&
                              (_data['company'] as String).isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Text(
                                _data['company'] as String,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ),
                          Wrap(
                            spacing: 16,
                            runSpacing: 10,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              if (widget.recordHeading != null || !_doc.isNew)
                                widget.recordHeading ??
                                    Text(
                                      _doc.data['name']?.toString() ??
                                          widget.schema.doctype,
                                      style: displayStyle(32),
                                    ),
                              StatusChip(
                                _dirty
                                    ? 'Unsaved changes'
                                    : status == 2
                                    ? 'Cancelled'
                                    : status == 1
                                    ? 'Submitted'
                                    : _doc.isNew
                                    ? 'New'
                                    : widget.schema.submittable
                                    ? 'Draft'
                                    : 'Saved',
                              ),
                            ],
                          ),
                          Wrap(
                            spacing: 10,
                            runSpacing: 4,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              if (widget.onRelated != null &&
                                  _doc.relatedActions.isNotEmpty)
                                PopupMenuButton<String>(
                                  enabled: !_locked,
                                  onSelected: _related,
                                  itemBuilder: (_) => [
                                    for (final action in _doc.relatedActions)
                                      PopupMenuItem(
                                        value: action,
                                        child: Text(action),
                                      ),
                                  ],
                                  child: const Padding(
                                    padding: EdgeInsets.all(12),
                                    child: Text('Create / copy ▾'),
                                  ),
                                ),
                              if (!_doc.isNew &&
                                  _doc.can('print') &&
                                  widget.onInvoicePreview != null)
                                TextButton.icon(
                                  onPressed: _locked || _dirty
                                      ? null
                                      : () =>
                                            widget.onInvoicePreview!(_doc.data),
                                  icon: const Icon(
                                    Icons.picture_as_pdf_outlined,
                                    size: 18,
                                  ),
                                  label: const Text('Invoice preview'),
                                ),
                              if (!_doc.isNew && widget.onActivity != null)
                                TextButton.icon(
                                  onPressed: _locked
                                      ? null
                                      : () => widget.onActivity!(_data),
                                  icon: const Icon(Icons.history, size: 18),
                                  label: const Text('Files & activity'),
                                ),
                              if (widget.onPartyDefaults != null &&
                                  canSave &&
                                  status == 0)
                                TextButton.icon(
                                  onPressed: _locked
                                      ? null
                                      : () => _perform('Save', party: true),
                                  icon: const Icon(
                                    Icons.person_outline,
                                    size: 18,
                                  ),
                                  label: const Text('Load party details'),
                                ),
                              if (widget.onPrepare != null &&
                                  canSave &&
                                  status == 0)
                                TextButton.icon(
                                  onPressed: _locked
                                      ? null
                                      : () => _perform('Save', prepare: true),
                                  icon: const Icon(
                                    Icons.calculate_outlined,
                                    size: 18,
                                  ),
                                  label: const Text('Update calculations'),
                                ),
                              if (widget.schema.submittable &&
                                  status == 0 &&
                                  !_doc.isNew &&
                                  _doc.can('submit') &&
                                  _doc.workflow.isEmpty)
                                TextButton(
                                  onPressed: _locked
                                      ? null
                                      : () => _perform('Submit'),
                                  child: const Text('Submit'),
                                ),
                              if (status == 1 &&
                                  _doc.can('cancel') &&
                                  _doc.workflow.isEmpty)
                                TextButton(
                                  onPressed: _locked
                                      ? null
                                      : () => _perform('Cancel'),
                                  child: const Text('Cancel document'),
                                ),
                              if (widget.onTransition != null)
                                for (final transition in _doc.transitions)
                                  TextButton(
                                    onPressed: _locked
                                        ? null
                                        : () => _perform(
                                            transition['action'] as String,
                                            workflow: true,
                                          ),
                                    child: Text(transition['action'] as String),
                                  ),
                            ],
                          ),
                          if (_unverified)
                            Panel(
                              border: true,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Outcome not confirmed',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  Text(
                                    _doc.isNew
                                        ? 'Locate the record in this workspace before starting another entry.'
                                        : 'Inspect the current server record before another change. This replaces the attempted values in this editor.',
                                  ),
                                  if (!_doc.isNew && widget.onReload != null)
                                    TextButton.icon(
                                      onPressed: _busy
                                          ? null
                                          : _inspectUnverified,
                                      icon: const Icon(Icons.refresh),
                                      label: const Text('Check current record'),
                                    ),
                                ],
                              ),
                            ),
                          if (_uncertain != null)
                            Panel(
                              border: true,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Outcome not confirmed',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const Text(
                                    'Check this original request. Closing an unposted attempt prevents it from being posted later; a completed request shows its result.',
                                  ),
                                  SelectableText(
                                    'Request: ${_uncertain!.requestId}',
                                  ),
                                  Wrap(
                                    spacing: 12,
                                    children: [
                                      FilledButton(
                                        onPressed: _busy
                                            ? null
                                            : () => _checkOutcome(),
                                        child: const Text('Check outcome'),
                                      ),
                                      TextButton(
                                        onPressed: _busy
                                            ? null
                                            : () => _checkOutcome(close: true),
                                        child: const Text(
                                          'Close unposted attempt',
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          if (_error != null)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              child: Semantics(
                                liveRegion: true,
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Icon(Icons.error_outline),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        _error!,
                                        style: const TextStyle(
                                          color: WorkspaceTheme.ink,
                                          height: 1.5,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          if (_notice != null)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              child: Semantics(
                                liveRegion: true,
                                child: Row(
                                  children: [
                                    TweenAnimationBuilder<double>(
                                      key: ValueKey(_revision),
                                      tween: Tween(
                                        begin: workspaceReduceMotion(context)
                                            ? 1.0
                                            : .55,
                                        end: 1,
                                      ),
                                      curve: Curves.easeOutCubic,
                                      duration: workspaceMotion(context),
                                      builder: (_, scale, child) =>
                                          Transform.scale(
                                            scale: scale,
                                            child: child,
                                          ),
                                      child: Icon(
                                        _dirty
                                            ? Icons.info_outline
                                            : Icons.check_circle_outline,
                                        size: 21,
                                        color: _dirty
                                            ? WorkspaceTheme.ink
                                            : const Color(0xFF2E634F),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        _notice!,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          if (_stale && !_doc.isNew && widget.onReload != null)
                            Align(
                              alignment: Alignment.centerLeft,
                              child: TextButton.icon(
                                onPressed: _busy ? null : _reloadConflict,
                                icon: const Icon(Icons.refresh),
                                label: const Text('Reload latest version'),
                              ),
                            ),
                          if (_errors.isNotEmpty)
                            DocumentErrorSummary(
                              errors: _errors,
                              onSelect: (path) =>
                                  _revealField(path, openRow: true),
                            ),
                          const SizedBox(height: 18),
                          if (guided)
                            Semantics(
                              header: true,
                              child: Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Text(
                                  steps[current].label,
                                  style: Theme.of(context).textTheme.titleLarge,
                                ),
                              ),
                            ),
                          Panel(
                            border: true,
                            child: DocumentFields(
                              visibleStepFields: guided
                                  ? steps[current].fields
                                  : null,
                              key: _fieldsKey,
                              scopeKey: (widget.scopeKey, _revision),
                              schema: widget.schema,
                              data: _data,
                              errors: _errors,
                              editable: !_locked && canSave,
                              onLink: widget.onLink,
                              openFieldFile: widget.openFieldFile,
                              onNewRow: widget.onNewRow,
                              onItemDefaults: widget.onItemDefaults,
                              onChanged: () => _update(() {
                                _dirty = true;
                                _notice = null;
                                if (_errors.isNotEmpty) {
                                  _errors = _validateFields();
                                  if (_errors.isEmpty) _error = null;
                                }
                              }),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (guided)
              DocumentEntryNavigation(
                index: current,
                count: steps.length,
                onBack: _locked || current == 0
                    ? null
                    : () => _moveToStep(steps[current - 1].key),
                onProceed: _locked || !canSave
                    ? null
                    : current + 1 < steps.length
                    ? () => _nextStep(steps[current], steps[current + 1])
                    : () => _perform('Save'),
              ),
          ],
        ),
      ),
    );
  }
}

class _DocumentPopEntry extends PopEntry<Object?> {
  _DocumentPopEntry(this.onBlocked);
  final VoidCallback onBlocked;
  @override
  final ValueNotifier<bool> canPopNotifier = ValueNotifier(true);
  @override
  void onPopInvokedWithResult(bool didPop, Object? result) {
    if (!didPop) onBlocked();
  }
}

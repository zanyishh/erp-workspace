import 'package:flutter/foundation.dart';

import '../../../core/models/erp_exception.dart';
import '../data/invoice_repository.dart';
import '../models/invoice_print_data.dart';
import '../models/invoice_paper.dart';
import '../models/invoice_templates.dart';

class InvoicePdfFile {
  InvoicePdfFile._(
    this._model,
    this._scope,
    Uint8List value,
    this.filename,
    this.paper,
  ) : bytes = Uint8List.fromList(value).asUnmodifiableView();
  final Object _model, _scope;
  final Uint8List bytes;
  final String filename;
  final InvoicePaper paper;
}

class InvoicePreviewViewModel extends ChangeNotifier {
  InvoicePreviewViewModel(
    this._repository, {
    required this.source,
    this.initialTemplate,
    required this._render,
  }) : _owner = _repository.identity {
    reload();
  }
  final InvoicePreviewRepository _repository;
  final Object _owner;
  final InvoicePreviewSource source;
  final InvoiceTemplate? initialTemplate;
  final Future<Uint8List> Function(
    InvoiceTemplate,
    InvoicePrintData,
    InvoicePaper,
  )
  _render;
  InvoicePaper _paper = InvoicePaper.a4;
  InvoicePaper get paper => _paper;
  bool _disposed = false, _authorized = false, _choseStyle = false;
  int _generation = 0, _styleVersion = 0;
  Object? _loadedScope, _dataScope, _writeToken, _errorScope;
  Object? _dataError;
  String? _problem;
  InvoicePrintData? _value;
  InvoicePdfFile? _file;
  late InvoiceTemplate _selected =
      initialTemplate ?? invoiceTemplateById('ledger');
  String _savedOverride = '';
  late Future<InvoicePrintData> _data;
  Future<InvoicePdfFile>? _pdf;
  static const _changed = ErpException(
    'Access changed. Open the current invoice preview again.',
  );
  late final Future<InvoicePrintData> _unavailable = _errorFuture(_changed);
  Object get _resourceScope =>
      (_owner, _repository.scope, source.kind, source.name);
  Object get scope => (_resourceScope, _generation);
  Object get pdfScope => (scope, _styleVersion);
  bool get _active =>
      !_disposed && _owner == _repository.identity && _repository.scope != null;
  bool isCurrent(Object captured) => _active && captured == scope;
  bool get _ready => _authorized && isCurrent(_loadedScope ?? Object());
  bool _currentRender(Object captured) => _ready && captured == pdfScope;
  Future<InvoicePrintData> get data =>
      _active && _dataScope == scope ? _data : _unavailable;
  Future<InvoicePdfFile>? get pdf => _ready ? _pdf : null;
  InvoicePdfFile? get currentFile =>
      _ready && _file != null && canUse(_file!) ? _file : null;
  InvoiceTemplate get selected => _selected;
  bool get choseStyle => _choseStyle;
  String get savedOverride => _ready ? _savedOverride : '';
  bool get working => !_disposed && _writeToken != null;
  Object? get dataError =>
      isCurrent(_errorScope ?? Object()) ? _dataError : null;
  String? get problem => _ready ? _problem : null;
  bool get canSaveStyle =>
      _ready &&
      source.kind == InvoiceSourceKind.native &&
      _value!.canSetTemplate &&
      _choseStyle &&
      _selected.id != _savedOverride;
  bool get canInherit =>
      _ready &&
      source.kind == InvoiceSourceKind.native &&
      _value!.canSetTemplate &&
      _savedOverride.isNotEmpty;
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<InvoicePrintData> _errorFuture(Object error) {
    final future = Future<InvoicePrintData>.error(error);
    future.ignore();
    return future;
  }

  void _require(Object captured) {
    if (!isCurrent(captured)) throw _changed;
  }

  void _requireRender(Object captured) {
    if (!_currentRender(captured)) throw _changed;
  }

  bool canUse(InvoicePdfFile file) =>
      _currentRender(file._scope) && identical(file._model, this);
  Future<InvoicePrintData> reload() {
    _generation++;
    _styleVersion++;
    _loadedScope = null;
    _value = null;
    _file = null;
    _pdf = null;
    _authorized = false;
    _dataError = null;
    _errorScope = null;
    _problem = null;
    _choseStyle = false;
    _savedOverride = '';
    _selected = initialTemplate ?? invoiceTemplateById('ledger');
    final captured = scope;
    _dataScope = captured;
    _data = _active ? _load(captured) : _errorFuture(_changed);
    _data.ignore();
    _notify();
    return _data;
  }

  Future<InvoicePrintData> _load(Object captured) async {
    try {
      final value = await _repository.source(source);
      _require(captured);
      _value = value;
      _loadedScope = captured;
      _authorized = true;
      _selected = initialTemplate ?? invoiceTemplateById(value.templateId);
      _savedOverride = value.templateOverride;
      _choseStyle = false;
      _styleVersion++;
      _startPdf(value);
      _notify();
      return value;
    } catch (error) {
      if (isCurrent(captured)) {
        _authorized = false;
        _file = null;
        _dataError = error;
        _errorScope = captured;
        _notify();
      }
      rethrow;
    }
  }

  String _filename(InvoiceTemplate style, InvoicePrintData value) {
    final basename = switch (source.kind) {
      InvoiceSourceKind.sample => 'Sample - ${style.name}',
      InvoiceSourceKind.original =>
        '${value.data['source_reference'] ?? value.data['name']} - ${style.name}',
      InvoiceSourceKind.native => '${source.name} - ${style.name}',
    };
    final suffix = _paper == InvoicePaper.a4 ? '' : ' - ${_paper.label}';
    return '${basename.replaceAll(RegExp(r'[/\\\x00-\x1f]'), '_')}$suffix.pdf';
  }

  void _startPdf(InvoicePrintData value) {
    _file = null;
    _pdf = _preview(value, _selected, pdfScope);
    _pdf!.ignore();
  }

  Future<InvoicePdfFile> _preview(
    InvoicePrintData value,
    InvoiceTemplate style,
    Object captured,
  ) async {
    final bytes = await _render(style, value, _paper);
    _requireRender(captured);
    final file = InvoicePdfFile._(
      this,
      captured,
      bytes,
      _filename(style, value),
      _paper,
    );
    _file = file;
    _notify();
    return file;
  }

  Object? prepareSelection() =>
      _ready && !working ? (this, scope, _styleVersion) : null;
  bool selectPaper(Object captured, InvoicePaper paper) {
    if (captured != prepareSelection()) return false;
    if (_paper == paper) return true;
    _paper = paper;
    _styleVersion++;
    _startPdf(_value!);
    _notify();
    return true;
  }

  bool selectTemplate(Object captured, InvoiceTemplate style) {
    if (!_ready || working || captured != (this, scope, _styleVersion)) {
      return false;
    }
    _selected = style;
    _choseStyle = true;
    _styleVersion++;
    _startPdf(_value!);
    _notify();
    return true;
  }

  void _rejectCached(Object error, Object captured) {
    if (!isCurrent(captured)) return;
    _authorized = false;
    _file = null;
    _dataError = error;
    _errorScope = captured;
    _data = _errorFuture(error);
    _notify();
  }

  Future<bool> saveStyle({bool inherit = false}) async {
    if (working || !(inherit ? canInherit : canSaveStyle)) return false;
    final captured = scope, token = Object(), id = inherit ? '' : _selected.id;
    final resource = _resourceScope;
    Object commandScope = captured;
    _writeToken = token;
    _problem = null;
    _notify();
    try {
      await _repository.saveTemplate(source.name, id);
      if (!_active || resource != _resourceScope) return false;
      final next = reload();
      commandScope = scope;
      await next;
      return isCurrent(commandScope);
    } catch (error) {
      if (isCurrent(commandScope)) {
        _problem = error.toString();
        _notify();
      }
      if (error is ErpException &&
          (error.permissionDenied || error.sessionExpired)) {
        _rejectCached(error, commandScope);
      }
      return false;
    } finally {
      if (identical(_writeToken, token)) {
        _writeToken = null;
        _notify();
      }
    }
  }

  Future<InvoicePdfFile> _fresh(
    Object captured,
    InvoiceTemplate selected,
    bool choseStyle,
  ) async {
    try {
      _requireRender(captured);
      final value = await _repository.source(source);
      _requireRender(captured);
      final style = source.kind == InvoiceSourceKind.sample || choseStyle
          ? selected
          : invoiceTemplateById(value.templateId);
      final bytes = await _render(style, value, _paper);
      _requireRender(captured);
      return InvoicePdfFile._(
        this,
        captured,
        bytes,
        _filename(style, value),
        _paper,
      );
    } catch (error) {
      if (error is ErpException &&
          (error.permissionDenied || error.sessionExpired) &&
          _currentRender(captured)) {
        _rejectCached(error, scope);
      }
      rethrow;
    }
  }

  Future<void> exportTo(
    Future<void> Function(InvoicePdfFile, Future<InvoicePdfFile> Function())
    platform,
  ) async {
    if (working || !_ready) return;
    final captured = pdfScope,
        token = Object(),
        selected = _selected,
        choseStyle = _choseStyle;
    _writeToken = token;
    _problem = null;
    _notify();
    try {
      final file = await _fresh(captured, selected, choseStyle);
      _requireRender(captured);
      await platform(file, () => _fresh(captured, selected, choseStyle));
    } finally {
      if (identical(_writeToken, token)) {
        _writeToken = null;
        _notify();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _file = null;
    _value = null;
    _authorized = false;
    super.dispose();
  }
}

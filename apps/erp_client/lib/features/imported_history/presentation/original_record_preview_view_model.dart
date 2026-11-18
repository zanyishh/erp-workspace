import 'package:flutter/foundation.dart';

import '../../../core/models/erp_exception.dart';
import '../data/history_repository.dart';
import '../models/history_models.dart';

class OriginalPdfFile {
  OriginalPdfFile._(this._model, this._scope, Uint8List value, this.filename)
    : bytes = Uint8List.fromList(value).asUnmodifiableView();
  final Object _model, _scope;
  final Uint8List bytes;
  final String filename;
}

class OriginalRecordPreviewViewModel extends ChangeNotifier {
  OriginalRecordPreviewViewModel(
    this._repository, {
    required this.name,
    required this._render,
  }) : _owner = _repository.identity {
    reload();
  }
  final ImportedHistoryRepository _repository;
  final Object _owner;
  final String name;
  final Future<Uint8List> Function(OriginalRecordData) _render;
  bool _disposed = false, _authorized = false;
  int _version = 0;
  Object? _resultScope, _exportToken;
  Object? _previewError;
  OriginalPdfFile? _file;
  late Future<OriginalPdfFile> _result;
  static const _changed = ErpException(
    'Access changed. Open the current original record again.',
  );
  late final Future<OriginalPdfFile> _unavailable = _errorFuture(_changed);
  Object get scope => (_owner, _repository.scope, name, _version);
  bool get _active =>
      !_disposed && _owner == _repository.identity && _repository.scope != null;
  bool isCurrent(Object value) => _active && value == scope;
  Future<OriginalPdfFile> get result =>
      _resultScope != null && isCurrent(_resultScope!) ? _result : _unavailable;
  OriginalPdfFile? get currentFile =>
      _resultScope != null && isCurrent(_resultScope!) && _authorized
      ? _file
      : null;
  bool get working => !_disposed && _exportToken != null;
  bool get errorInPreview =>
      _previewError != null && _resultScope != null && isCurrent(_resultScope!);
  Object? get previewError => errorInPreview ? _previewError : null;
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<OriginalPdfFile> _errorFuture(Object error) {
    final future = Future<OriginalPdfFile>.error(error);
    future.ignore();
    return future;
  }

  void _require(Object captured, {bool cached = false}) {
    if (!isCurrent(captured) || cached && !_authorized) throw _changed;
  }

  bool canUse(OriginalPdfFile file) =>
      _authorized && identical(file._model, this) && isCurrent(file._scope);
  Future<OriginalPdfFile> reload() {
    _version++;
    final captured = scope;
    _resultScope = captured;
    _file = null;
    _authorized = false;
    _previewError = null;
    _result = _active ? _preview(captured) : _errorFuture(_changed);
    _result.ignore();
    _notify();
    return _result;
  }

  Future<OriginalPdfFile> _preview(Object captured) async {
    final file = await _fresh(captured, cached: false);
    _require(captured);
    _file = file;
    _authorized = true;
    _previewError = null;
    _notify();
    return file;
  }

  Future<OriginalPdfFile> _fresh(
    Object captured, {
    required bool cached,
  }) async {
    try {
      _require(captured, cached: cached);
      final data = await _repository.printData(name);
      _require(captured, cached: cached);
      final bytes = await _render(data);
      _require(captured, cached: cached);
      final reference = data.data['reference']?.toString();
      final identity = reference == null || reference.isEmpty
          ? data.data['title']
          : reference;
      final filename =
          '$identity - ${data.data['document_label']} - Original source copy.pdf'
              .replaceAll(RegExp(r'[/\\\x00-\x1f]'), '_');
      return OriginalPdfFile._(this, captured, bytes, filename);
    } catch (error) {
      final rejected =
          error is ErpException &&
          (error.permissionDenied || error.sessionExpired);
      if (isCurrent(captured) && (!cached || rejected)) {
        _file = null;
        _authorized = false;
        _previewError = error;
        if (cached) _result = _errorFuture(error);
        _notify();
      }
      rethrow;
    }
  }

  Future<void> exportTo(
    Future<void> Function(OriginalPdfFile, Future<OriginalPdfFile> Function())
    platform,
  ) async {
    if (working || currentFile == null) return;
    final captured = scope, token = Object();
    _exportToken = token;
    _notify();
    try {
      final first = await _fresh(captured, cached: true);
      _require(captured, cached: true);
      await platform(first, () => _fresh(captured, cached: true));
    } finally {
      if (identical(_exportToken, token)) {
        _exportToken = null;
        _notify();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _version++;
    _file = null;
    _authorized = false;
    _previewError = null;
    super.dispose();
  }
}

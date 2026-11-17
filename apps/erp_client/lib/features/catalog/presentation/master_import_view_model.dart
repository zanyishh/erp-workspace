import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../../core/models/erp_exception.dart';
import '../data/master_import_repository.dart';
import '../models/catalog_models.dart';

class MasterImportViewModel extends ChangeNotifier {
  MasterImportViewModel(
    this._repository, {
    required this.doctype,
    required this.company,
    required this._chooseFile,
    required this._saveFile,
  }) : _owner = _repository.identity {
    _validatedScope = scope;
    _stateScope = scope;
  }
  final MasterImportRepository _repository;
  final Object _owner;
  final String doctype, company;
  final Future<ImportFile?> Function() _chooseFile;
  final Future<void> Function(String, Uint8List) _saveFile;
  String? _content, _filename, _problem;
  MasterImportPreview? _preview;
  bool _finished = false, _uncertain = false, _disposed = false;
  int _version = 0;
  Object? _busyToken, _validatedScope, _stateScope, _choosingScope;
  Object get scope => (_owner, _repository.scope, _version, doctype, company);
  Object get identity => _owner;
  bool get busy => !_disposed && _busyToken != null;
  bool isCurrent(Object captured) =>
      !_disposed &&
      _owner == _repository.identity &&
      _repository.scope != null &&
      captured == scope;
  bool get _stateCurrent => _stateScope != null && isCurrent(_stateScope!);
  bool get _validated => isCurrent(scope) && _validatedScope == scope;
  String? get filename => _stateCurrent ? _filename : null;
  String? get problem => _stateCurrent ? _problem : null;
  MasterImportPreview? get preview => _stateCurrent ? _preview : null;
  bool get finished => _stateCurrent && _finished;
  bool get uncertain => _stateCurrent && _uncertain;
  bool get done => finished || preview?.alreadyImported == true;
  bool get canConfirm =>
      _validated &&
      !busy &&
      !done &&
      _content != null &&
      preview != null &&
      preview!.count > 0 &&
      preview!.errors.isEmpty;
  static const _changed = ErpException(
    'Workspace access changed. Refresh this workspace.',
    permissionDenied: true,
  );
  void _notify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  void invalidate() {
    if (_disposed) {
      return;
    }
    _version++;
    _notify();
  }

  void _clearState() {
    _content = _filename = _problem = null;
    _preview = null;
    _finished = _uncertain = false;
  }

  Future<void> revalidate() async {
    if (_disposed ||
        _owner != _repository.identity ||
        _repository.scope == null) {
      throw _changed;
    }
    final captured = scope;
    await _repository.importMasters(doctype, 'template');
    if (!isCurrent(captured)) {
      throw _changed;
    }
    _clearState();
    _stateScope = captured;
    _validatedScope = captured;
    _notify();
  }

  Future<void> _run(Future<void> Function(Object) action) async {
    if (_disposed || busy || !_validated) {
      return;
    }
    final captured = scope, token = Object();
    _busyToken = token;
    _problem = null;
    _notify();
    try {
      await action(captured);
    } catch (error) {
      if (isCurrent(captured)) {
        _problem = error.toString();
        _stateScope = captured;
        _notify();
      }
    } finally {
      if (identical(_busyToken, token)) {
        _busyToken = null;
        _notify();
      }
    }
  }

  Future<void> template() => _run((captured) async {
    final data = await _repository.importMasters(doctype, 'template');
    if (!isCurrent(captured)) {
      return;
    }
    await _saveFile(
      '$doctype template.csv',
      Uint8List.fromList(utf8.encode('${data.columns.join(',')}\r\n')),
    );
  });
  void _selectFilename(String name, Object captured) {
    _content = null;
    _preview = null;
    _filename = name;
    _finished = _uncertain = false;
    _stateScope = captured;
    _notify();
  }

  /// File-service progress preserves the selected filename while preview loads.
  void selectedFilename(String name) {
    final captured = _choosingScope;
    if (captured != null && busy && isCurrent(captured)) {
      _selectFilename(name, captured);
    }
  }

  Future<void> choose() async {
    if (uncertain) {
      return;
    }
    await _run((captured) async {
      _choosingScope = captured;
      try {
        final file = await _chooseFile();
        if (file == null || !isCurrent(captured)) {
          return;
        }
        _selectFilename(file.name, captured);
        if (file.bytes.length > masterImportMaxBytes) {
          throw const FormatException('Choose a CSV file of up to 256 KB.');
        }
        final content = utf8.decode(file.bytes);
        if (!isCurrent(captured)) {
          return;
        }
        final value = await _repository.importMasters(
          doctype,
          'preview',
          content: content,
        );
        if (isCurrent(captured)) {
          _content = content;
          _preview = value;
          _stateScope = captured;
          _notify();
        }
      } finally {
        _choosingScope = null;
      }
    });
  }

  Future<void> confirm() async {
    if (!canConfirm) {
      return;
    }
    await _run((captured) async {
      final content = _content;
      try {
        final value = await _repository.importMasters(
          doctype,
          'confirm',
          content: content,
        );
        if (isCurrent(captured)) {
          _finished = true;
          _uncertain = false;
          _preview = value;
          _content = null;
          _stateScope = captured;
          _notify();
        }
      } catch (error) {
        if (isCurrent(captured) &&
            !(error is ErpException &&
                (error.validationRejected ||
                    error.permissionDenied ||
                    error.sessionExpired))) {
          _uncertain = true;
          _stateScope = captured;
          _notify();
        }
        rethrow;
      }
    });
  }

  Future<void> check() async {
    if (!uncertain || _content == null) {
      return;
    }
    await _run((captured) async {
      final value = await _repository.importMasters(
        doctype,
        'preview',
        content: _content,
      );
      if (!isCurrent(captured)) {
        return;
      }
      _preview = value;
      _finished = value.alreadyImported;
      _uncertain = !_finished;
      if (_finished) {
        _content = null;
      } else {
        _problem = 'No completed receipt is available yet. Checking or retrying this same file will not import it twice.';
      }
      _stateScope = captured;
      _notify();
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _clearState();
    super.dispose();
  }
}

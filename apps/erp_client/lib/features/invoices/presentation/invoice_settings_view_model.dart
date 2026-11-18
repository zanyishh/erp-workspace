import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../../core/models/erp_exception.dart';
import '../data/invoice_repository.dart';
import '../models/invoice_profile.dart';
import '../models/invoice_templates.dart';

class InvoiceSettingsViewModel extends ChangeNotifier {
  InvoiceSettingsViewModel(this._repository, {required this._pickLogo})
    : _owner = _repository.identity {
    reload();
  }
  final InvoiceSettingsRepository _repository;
  final Object _owner;
  final Future<Uint8List?> Function() _pickLogo;
  bool _disposed = false,
      _canManage = false,
      _stale = false,
      _uncertain = false;
  int _generation = 0, _draftVersion = 0;
  Object? _loadedScope, _writeToken;
  String _revision = '', _error = '';
  Map<String, String> _values = {}, _original = {};
  Map<String, String>? _attempt;
  String? _attemptedRevision;
  Uint8List? _image;
  late Future<void> _loaded;
  static const _changed = ErpException(
    'Workspace access changed. Refresh this workspace.',
    permissionDenied: true,
  );
  Object get scope => (_owner, _repository.scope);
  bool get _active =>
      !_disposed && _owner == _repository.identity && _repository.scope != null;
  bool isCurrent(Object value) => _active && value == scope;
  bool get _ready => isCurrent(_loadedScope ?? Object());
  Future<void> get loaded => _loaded;
  int get draftVersion => _draftVersion;
  Map<String, String> get values =>
      _ready ? Map.unmodifiable(_values) : const {};
  Uint8List? get image => _ready ? _image : null;
  bool get canManage => _ready && _canManage;
  bool get busy => !_disposed && _writeToken != null;
  bool get stale => _ready && _stale;
  bool get uncertain => _ready && _uncertain;
  String get error => _ready ? _error : '';
  bool get _dirty =>
      _original.isNotEmpty &&
      _saveValues.entries.any((e) => _original[e.key] != e.value);
  bool get dirty => _ready && _dirty;
  Map<String, String> get _saveValues => {
    for (final e in _values.entries) e.key: e.value.trim(),
  };
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void _clearPrivate() {
    _values = {};
    _original = {};
    _image = null;
    _canManage = false;
    _attempt = null;
    _attemptedRevision = null;
    _uncertain = false;
    _draftVersion++;
  }

  Future<void> reload({bool keepEdits = false}) {
    final version = ++_generation, captured = scope;
    _loaded = _active
        ? _load(version, captured, keepEdits)
        : Future.error(_changed);
    _loaded.ignore();
    return _loaded;
  }

  Future<void> _load(int version, Object captured, bool keepEdits) async {
    try {
      final profile = await _repository.settings();
      if (!isCurrent(captured) || version != _generation) throw _changed;
      _loadedScope = captured;
      _canManage = profile.canManage;
      if (keepEdits && _canManage && _dirty) {
        if (_revision != profile.revision) {
          _stale = true;
          _error = 'Someone changed these settings. Reload before editing the latest version.';
        }
        _notify();
        return;
      }
      _revision = profile.revision;
      _values = {
        for (final key in invoiceSettingFields)
          if (!const {
                'accent_color',
                'signatory_name',
                'print_footer',
              }.contains(key) ||
              profile.settings.containsKey(key))
            key: _canManage ? (profile.settings[key] ?? '') : '',
      };
      _values['template_id'] = invoiceTemplateById(
        profile.settings['template_id'] ?? 'ledger',
      ).id;
      final logo = _values['logo_base64']!;
      _image = logo.isEmpty ? null : base64Decode(logo).asUnmodifiableView();
      _original = Map.of(_saveValues);
      _error = '';
      _stale = _uncertain = false;
      _attempt = null;
      _attemptedRevision = null;
      _draftVersion++;
      _notify();
    } catch (error) {
      if (isCurrent(captured) && version == _generation) {
        if (error is ErpException &&
            (error.permissionDenied || error.sessionExpired)) {
          _clearPrivate();
          _loadedScope = captured;
        }
        _error = error.toString();
        _notify();
      }
      rethrow;
    }
  }

  Future<void> revalidate() => reload(keepEdits: true);
  bool get _editable => canManage && !busy && !_uncertain;
  void change(String key, String value) {
    if (!_editable ||
        !_values.containsKey(key) ||
        key == 'template_id' ||
        key == 'logo_base64') {
      return;
    }
    _values = {..._values, key: value};
    _draftVersion++;
    _notify();
  }

  Object? prepareTemplateChoice() => _editable ? scope : null;
  bool acceptTemplateChoice(Object captured, String id) {
    if (!_editable || !isCurrent(captured)) return false;
    _values = {..._values, 'template_id': invoiceTemplateById(id).id};
    _draftVersion++;
    _notify();
    return true;
  }

  void clearLogo() {
    if (!_editable) return;
    _values = {..._values, 'logo_base64': ''};
    _image = null;
    _draftVersion++;
    _notify();
  }

  Future<void> chooseLogo() async {
    if (!_editable) return;
    final captured = scope, token = Object();
    _writeToken = token;
    _error = '';
    _notify();
    try {
      final bytes = await _pickLogo();
      if (bytes != null && isCurrent(captured) && canManage) {
        _image = Uint8List.fromList(bytes).asUnmodifiableView();
        _values = {..._values, 'logo_base64': base64Encode(_image!)};
        _draftVersion++;
        _notify();
      }
    } on FormatException catch (error) {
      if (isCurrent(captured)) _error = error.message;
    } catch (_) {
      if (isCurrent(captured)) {
        _error = 'The image could not be opened. Choose another PNG or JPEG.';
      }
    } finally {
      if (identical(_writeToken, token)) {
        _writeToken = null;
        _notify();
      }
    }
  }

  String? validateField(String key, String raw) {
    final value = raw.trim();
    if (key == 'accent_color' &&
        value.isNotEmpty &&
        !invoiceAccentColors.containsKey(value)) {
      return 'Choose an available invoice accent color.';
    }
    if (const {
          'print_footer',
          'signatory_name',
          'bank_name',
          'account_holder',
          'upi_name',
        }.contains(key) &&
        (value.runes.length > 100 ||
            RegExp(r'[<>\x00-\x1f\x7f]').hasMatch(value))) {
      return 'Use one line of up to 100 characters without angle brackets.';
    }
    if (key == 'account_number') {
      if (value.isEmpty &&
          [
            'bank_name',
            'account_holder',
            'ifsc',
          ].any((k) => (_values[k] ?? '').trim().isNotEmpty)) {
        return 'Enter the account number for these bank details.';
      }
      if (value.isNotEmpty &&
          !RegExp(r'^[A-Za-z0-9]{1,34}$')
              .hasMatch(value.replaceAll(RegExp(r'[ -]'), ''))) {
        return 'Use up to 34 letters or digits.';
      }
    }
    if (key == 'ifsc' &&
        value.isNotEmpty &&
        !RegExp(r'^[A-Za-z]{4}0[A-Za-z0-9]{6}$').hasMatch(value)) {
      return 'Enter an 11-character IFSC, such as ABCD0123456.';
    }
    if (key == 'upi_id' &&
        value.isNotEmpty &&
        !RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]*@[A-Za-z0-9][A-Za-z0-9.-]*$')
            .hasMatch(value)) {
      return 'Enter the UPI ID provided by your payment app.';
    }
    if (key == 'upi_id' &&
        value.isEmpty &&
        (_values['upi_name'] ?? '').trim().isNotEmpty) {
      return 'Enter the UPI ID for this payee.';
    }
    return null;
  }

  void _retainUncertainAttempt() {
    if (_disposed || _owner != _repository.identity || _attempt == null) return;
    _uncertain = true;
    _error = 'The save outcome is not confirmed. Check the saved settings before making another change.';
    _notify();
  }

  Future<bool> save() async {
    if (!canManage || busy || _stale || !_dirty && !_uncertain) return false;
    if (_saveValues.entries.any((e) => validateField(e.key, e.value) != null)) {
      return false;
    }
    _attempt ??= Map.unmodifiable(_saveValues);
    _attemptedRevision ??= _revision;
    final captured = scope, token = Object();
    _writeToken = token;
    _error = '';
    _notify();
    try {
      await _repository.saveSettings(_attempt!, _attemptedRevision!);
      if (!isCurrent(captured)) {
        _retainUncertainAttempt();
        return false;
      }
      return true;
    } catch (error) {
      if (!isCurrent(captured)) {
        _retainUncertainAttempt();
        return false;
      }
      final rejected =
          error is ErpException &&
          (error.validationRejected ||
              error.permissionDenied ||
              error.sessionExpired ||
              error.staleDocument);
      if (_uncertain || !rejected) {
        _uncertain = true;
        try {
          return await _readAttempt(captured);
        } catch (checkError) {
          if (isCurrent(captured)) {
            _error =
                'Save outcome not confirmed. Check the saved settings before making another change. $checkError';
          }
        }
      } else {
        _attempt = null;
        _attemptedRevision = null;
        _stale = error.staleDocument;
        _error = _stale
            ? 'Someone changed these settings. Reload before editing the latest version.'
            : error.toString();
      }
      return false;
    } finally {
      if (identical(_writeToken, token)) {
        _writeToken = null;
        _notify();
      }
    }
  }

  Future<bool> _readAttempt(Object captured) async {
    final expected = _attempt;
    if (expected == null) return false;
    final profile = await _repository.settings();
    if (!isCurrent(captured)) return false;
    if (!profile.canManage) {
      _clearPrivate();
      _loadedScope = captured;
      _notify();
      return false;
    }
    if (expected.entries.every((e) => profile.settings[e.key] == e.value)) {
      return true;
    }
    _stale = profile.revision != _attemptedRevision;
    if (_stale) {
      _uncertain = false;
      _attempt = null;
      _attemptedRevision = null;
    }
    _error = _stale
        ? 'The saved settings have changed. Inspect them before replacing your retained edits.'
        : 'The save is not confirmed yet. Check again or retry exactly the same settings; the saved revision prevents applying them twice.';
    _notify();
    return false;
  }

  Future<bool> checkSaved() async {
    if (busy || !uncertain) return false;
    final captured = scope, token = Object();
    _writeToken = token;
    _error = '';
    _notify();
    try {
      return await _readAttempt(captured);
    } catch (error) {
      if (isCurrent(captured)) _error = 'Save outcome not confirmed. $error';
      return false;
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
    _clearPrivate();
    super.dispose();
  }
}

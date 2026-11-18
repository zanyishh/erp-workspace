import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../../core/models/erp_exception.dart';
import '../../../core/models/json_values.dart';
import '../data/invoice_composer_repository.dart';
import '../models/invoice_compose.dart';
import '../models/invoice_templates.dart';

class InvoiceDraftReceipt {
  const InvoiceDraftReceipt._(
    this._model,
    this._scope,
    this.name,
    this._requestId,
    this._prepared, {
    this.warning,
  });
  final Object _model, _scope;
  final String name, _requestId;
  final bool _prepared;
  final String? warning;
}

class RemovedInvoiceLine {
  const RemovedInvoiceLine._(this._scope, this.line, this.index);
  final Object _scope;
  final InvoiceDraftLine line;
  final int index;
}

class InvoiceComposerViewModel extends ChangeNotifier {
  InvoiceComposerViewModel(
    this._repository, {
    this.initialTemplate,
    String Function()? newRequestId,
  }) : _owner = _repository.identity,
       _newRequestId = newRequestId ?? _randomId {
    _style = initialTemplate ?? '';
    _displayScope = scope;
    revalidate();
  }
  final InvoiceComposerRepository _repository;
  final Object _owner;
  final String? initialTemplate;
  final String Function() _newRequestId;
  bool _disposed = false,
      _uncertain = false,
      _prepared = false,
      _showErrors = false;
  int _defaultsGeneration = 0;
  Object? _command, _displayScope;
  String _customer = '',
      _posting = '',
      _due = '',
      _originalDate = '',
      _style = '',
      _companyStyle = '',
      _error = '',
      _requestId = '',
      _attemptedReview = '';
  List<InvoiceDraftLine> _lines = [InvoiceDraftLine()];
  InvoiceReview? _reviewed;
  Map<String, Object?>? _reviewedDraft, _attempt;
  bool? _attemptRecovery;
  InvoiceDraftReceipt? _receipt;
  late Future<void> _loaded;
  static String _randomId() {
    final random = Random.secure();
    return List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }

  Object get scope => (this, _owner, _repository.scope);
  bool get _sameOwner => !_disposed && _owner == _repository.identity;
  bool get _active => _sameOwner && _repository.scope != null;
  bool isCurrent(Object captured) => _active && captured == scope;
  bool get _visible => isCurrent(_displayScope ?? Object());
  String get company => _repository.company;
  String get customer => _visible ? _customer : '';
  String get posting => _visible ? _posting : '';
  String get due => _visible ? _due : '';
  String get style => _visible ? _style : initialTemplate ?? '';
  String get companyStyle => _visible ? _companyStyle : '';
  String get error => _visible ? _error : '';
  String get requestId => _visible ? _requestId : '';
  List<InvoiceDraftLine> get lines =>
      _visible ? List.unmodifiable(_lines) : const [];
  InvoiceReview? get reviewed => _visible ? _reviewed : null;
  bool get showErrors => _visible && _showErrors;
  bool get busy => !_disposed && _command != null;
  bool get uncertain => _visible && _uncertain;
  bool get prepared => _visible && _prepared;
  bool get editable => _visible && !busy && !_uncertain && _receipt == null;
  bool get hasEdits =>
      _visible &&
      (_posting != _originalDate ||
          _customer.isNotEmpty ||
          _due.isNotEmpty ||
          _style != (initialTemplate ?? '') ||
          _lines.length != 1 ||
          _lines.any(
            (r) => r.item.isNotEmpty || r.rate.isNotEmpty || r.qty != '1',
          ));
  Future<void> get loaded => _loaded;
  Map<String, Object?> get draft => immutableJsonMap({
    'company': company,
    'customer': customer.trim(),
    'posting_date': posting,
    'due_date': due,
    'template_id': style,
    'items': [for (final row in lines) row.values],
  });
  InvoiceLeaveState get leaveState => busy || _sameOwner && _receipt != null
      ? InvoiceLeaveState.busy
      : _sameOwner && _uncertain && !_prepared
      ? InvoiceLeaveState.blocked
      : _sameOwner && _uncertain
      ? InvoiceLeaveState.pending
      : hasEdits
      ? InvoiceLeaveState.discard
      : InvoiceLeaveState.free;
  bool get canPop => leaveState == InvoiceLeaveState.free;
  bool canConfirmLeave(Object captured) {
    final state = leaveState;
    return _sameOwner &&
        captured == scope &&
        state != InvoiceLeaveState.busy &&
        state != InvoiceLeaveState.blocked;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> revalidate() {
    if (_sameOwner && _receipt != null && !canUse(_receipt!)) {
      // A previous confirmation cannot authorize a handoff under new access.
      // Retain its exact attempt and durable reference for current recovery.
      _receipt = null;
      _uncertain = true;
      _error = 'Access changed before the save was confirmed here. Check the same save before starting another invoice.';
      _notify();
    }
    final captured = scope, generation = ++_defaultsGeneration;
    _loaded = _active ? _defaults(captured, generation) : Future.value();
    _loaded.ignore();
    return _loaded;
  }

  Future<void> _defaults(Object captured, int generation) async {
    try {
      final value = await _repository.defaults();
      if (!isCurrent(captured) || generation != _defaultsGeneration) return;
      _displayScope = captured;
      if (_posting.isEmpty) _posting = _originalDate = value.postingDate;
      _companyStyle = invoiceTemplateById(value.templateId).name;
      if (!busy && !_uncertain && _requestId.isEmpty) {
        _reviewed = null;
        _reviewedDraft = null;
      }
      _notify();
    } catch (error) {
      if (isCurrent(captured) && generation == _defaultsGeneration) {
        _error = error.toString();
        _notify();
      }
      rethrow;
    }
  }

  void _edit(VoidCallback update) {
    if (!editable) return;
    update();
    _reviewed = null;
    _reviewedDraft = null;
    _attempt = null;
    _attemptRecovery = null;
    _requestId = _attemptedReview = _error = '';
    _prepared = false;
    _notify();
  }

  void changeCustomer(String value) => _edit(() => _customer = value);
  void changeDate(String value, {bool due = false}) => _edit(() {
    if (due) {
      _due = value;
    } else {
      _posting = value;
    }
  });
  void changeStyle(String value) => _edit(() => _style = value);
  void addLine() {
    if (_lines.length < 100) {
      _edit(() => _lines = [..._lines, InvoiceDraftLine()]);
    }
  }

  void changeLine(Object id, {String? item, String? qty, String? rate}) =>
      _edit(() {
        _lines = [
          for (final row in _lines)
            row.id == id ? row.copyWith(item: item, qty: qty, rate: rate) : row,
        ];
      });
  void moveLine(Object id, {required bool up}) {
    final from = _lines.indexWhere((row) => row.id == id);
    final to = up ? from - 1 : from + 1;
    if (from < 0 || to < 0 || to >= _lines.length) return;
    _edit(() {
      final reordered = [..._lines];
      final line = reordered.removeAt(from);
      reordered.insert(to, line);
      _lines = reordered;
    });
  }

  RemovedInvoiceLine? removeLine(Object id) {
    if (!editable) return null;
    final index = _lines.indexWhere((r) => r.id == id);
    if (index < 0) return null;
    final removed = RemovedInvoiceLine._(scope, _lines[index], index);
    _edit(() => _lines = [..._lines]..removeAt(index));
    return removed;
  }

  bool restoreLine(RemovedInvoiceLine removed) {
    if (!editable ||
        !isCurrent(removed._scope) ||
        _lines.any((r) => r.id == removed.line.id) ||
        _lines.length >= 100) {
      return false;
    }
    _edit(
      () =>
          _lines = [..._lines]
            ..insert(removed.index.clamp(0, _lines.length), removed.line),
    );
    return true;
  }

  bool get dueBeforeInvoice =>
      due.isNotEmpty && posting.isNotEmpty && due.compareTo(posting) < 0;

  bool validate() {
    if (!editable) return false;
    _showErrors = true;
    final valid =
        _customer.trim().isNotEmpty &&
        _posting.isNotEmpty &&
        !dueBeforeInvoice &&
        _lines.isNotEmpty &&
        _lines.every((r) => r.valid);
    if (!valid) {
      _error = _lines.isEmpty
          ? 'Add at least one invoice item.'
          : 'Check the highlighted fields before reviewing.';
    }
    _notify();
    return valid;
  }

  Future<bool> review() async {
    if (!editable || !validate()) return false;
    final captured = scope, token = Object(), snapshot = draft;
    _command = token;
    _error = '';
    _notify();
    try {
      final value = await _repository.review(snapshot);
      if (!isCurrent(captured)) return false;
      _reviewed = value;
      _reviewedDraft = snapshot;
      _notify();
      return true;
    } catch (error) {
      if (isCurrent(captured)) {
        _error = error.toString();
        _notify();
      }
      return false;
    } finally {
      _finish(token);
    }
  }

  void _finish(Object token) {
    if (identical(_command, token)) {
      _command = null;
      _notify();
    }
  }

  void _unknown() {
    if (!_sameOwner) return;
    _uncertain = true;
    _error = 'Sign in again and retry the same save to retrieve the draft.';
    _notify();
  }

  InvoiceDraftReceipt _confirm(String name) {
    if (name.isEmpty) {
      throw const ErpException(
        'The saved invoice could not be identified. Check the same request.',
      );
    }
    _uncertain = false;
    _receipt = InvoiceDraftReceipt._(this, scope, name, _requestId, _prepared);
    _notify();
    return _receipt!;
  }

  Future<InvoiceDraftReceipt?> save() async {
    if (!_visible || busy || _reviewed == null || _receipt != null) return null;
    _requestId = _requestId.isEmpty ? _newRequestId() : _requestId;
    _attempt ??= _reviewedDraft!;
    _attemptRecovery ??= _repository.supportsRecovery;
    if (_attemptedReview.isEmpty) _attemptedReview = _reviewed!.token;
    final captured = scope, token = Object(), wasUncertain = _uncertain;
    _command = token;
    _error = '';
    _notify();
    var writeSent = false;
    try {
      if (_attemptRecovery!) {
        final operation = await _repository.prepare(_requestId);
        if (!_sameOwner) return null;
        _prepared = true;
        if (!isCurrent(captured)) {
          _unknown();
          return null;
        }
        if (operation.state == 'completed') return _confirm(operation.name!);
        if (operation.state != 'prepared') {
          throw const ErpException(
            'This request was closed. Check its status before editing.',
          );
        }
      }
      writeSent = true;
      final name = await _repository.save(
        _attempt!,
        _requestId,
        _attemptedReview,
      );
      if (!isCurrent(captured)) {
        _unknown();
        return null;
      }
      return _confirm(name);
    } catch (error) {
      if (!_sameOwner) return null;
      if (!isCurrent(captured)) {
        if (writeSent || _prepared) _unknown();
        return null;
      }
      if (error is ErpException && error.validationRejected) {
        if (wasUncertain && !_prepared) {
          // Rejection of this retry cannot disprove an earlier committed write.
          _uncertain = true;
          _error =
              'The save could not be confirmed. Retry the same request or inspect its saved result before starting another invoice. $error';
          _notify();
          return null;
        }
        if (_prepared) {
          try {
            final closed = await _repository.status(_requestId, close: true);
            if (!isCurrent(captured)) {
              _unknown();
              return null;
            }
            if (closed.state == 'completed') return _confirm(closed.name!);
            if (closed.state != 'closed') {
              throw const ErpException('The request is not closed yet.');
            }
            await _repository.acknowledge(_requestId);
            if (!isCurrent(captured)) {
              _unknown();
              return null;
            }
          } catch (closing) {
            if (_sameOwner) {
              _uncertain = true;
              _error = '$error Check this request before editing. $closing';
              _notify();
            }
            return null;
          }
        }
        _clearAttempt();
        _error = error.toString();
      } else {
        _uncertain = wasUncertain || writeSent || _prepared;
        _error = _uncertain
            ? 'The save could not be confirmed. Check its status before starting another invoice. $error'
            : 'Could not prepare a recoverable save. Your entry is unchanged; try Save draft again. $error';
      }
      _notify();
      return null;
    } finally {
      _finish(token);
    }
  }

  void _clearAttempt() {
    _reviewed = null;
    _reviewedDraft = null;
    _attempt = null;
    _attemptRecovery = null;
    _requestId = _attemptedReview = '';
    _prepared = _uncertain = false;
  }

  Future<InvoiceDraftReceipt?> checkSave({bool close = false}) async {
    if (!_visible || busy || !_prepared || _receipt != null) return null;
    final captured = scope, token = Object();
    _command = token;
    _error = '';
    _notify();
    try {
      final value = await _repository.status(_requestId, close: close);
      if (!isCurrent(captured)) return null;
      if (value.state == 'completed') return _confirm(value.name!);
      if (value.state == 'closed') {
        try {
          await _repository.acknowledge(_requestId);
        } catch (_) {}
        if (!isCurrent(captured)) return null;
        _clearAttempt();
        _error =
            'The request was closed without saving. Review your invoice again.';
      } else {
        _error = 'The outcome is not confirmed. Check again or close this unposted request before editing.';
      }
      _notify();
    } catch (error) {
      if (isCurrent(captured)) {
        _error = error.toString();
        _notify();
      }
    } finally {
      _finish(token);
    }
    return null;
  }

  bool canUse(InvoiceDraftReceipt receipt) =>
      identical(receipt._model, this) && isCurrent(receipt._scope);
  Future<void> acknowledge(InvoiceDraftReceipt receipt) async {
    if (!canUse(receipt) ||
        !identical(receipt, _receipt) ||
        !receipt._prepared) {
      return;
    }
    try {
      await _repository.acknowledge(receipt._requestId);
    } catch (_) {}
  }

  Future<List<Map<String, dynamic>>> searchLinks(
    String type,
    String query,
  ) async {
    if (!editable) return const [];
    final captured = scope;
    final rows = await _repository.searchLinks(type, query);
    return isCurrent(captured) ? rows : const [];
  }

  Future<InvoiceDraftReceipt?> completeAdvanced(
    String name,
    Object captured,
  ) async {
    if (!isCurrent(captured)) return null;
    String? warning;
    if (_style.isNotEmpty) {
      try {
        await _repository.setTemplate(name, _style);
      } catch (error) {
        warning =
            'Draft $name was saved. Its print template could not be changed. $error';
      }
    }
    return isCurrent(captured)
        ? InvoiceDraftReceipt._(
            this,
            captured,
            name,
            '',
            false,
            warning: warning,
          )
        : null;
  }

  void explainBlockedLeave() {
    if (leaveState == InvoiceLeaveState.blocked) {
      _error = 'Check the same save before leaving. Its result has not been confirmed.';
      _notify();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _command = null;
    _attempt = _reviewedDraft = null;
    _reviewed = null;
    super.dispose();
  }
}

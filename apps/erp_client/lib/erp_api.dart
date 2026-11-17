import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'core/models/erp_exception.dart';
import 'core/models/access_source.dart';
import 'erp_models.dart';
import 'native_models.dart';
import 'native_reports.dart';
import 'workspace_context.dart';
import 'knitting_models.dart';
export 'core/models/erp_exception.dart';

part 'invoice_api.dart';
part 'imported_history_api.dart';

Uri validateServiceOrigin(
  Uri uri, {
  required bool isAndroid,
  required bool isRelease,
  required bool isProfile,
}) {
  final loopback = [
    'localhost',
    '127.0.0.1',
    '::1',
    '10.0.2.2',
  ].contains(uri.host);
  if (uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      uri.hasQuery ||
      uri.hasFragment ||
      (uri.path.isNotEmpty && uri.path != '/') ||
      !(uri.scheme == 'https' || (uri.scheme == 'http' && loopback))) {
    throw const ErpException(
      'This app could not connect to its configured service. Contact your workspace manager.',
    );
  }
  // Dart-owned sockets do not enforce Android's network security XML.
  if (isAndroid && (isRelease || isProfile) && uri.scheme != 'https') {
    throw const ErpException(
      'This app needs a secure HTTPS workspace service. Contact your workspace manager.',
    );
  }
  return uri.replace(path: '', query: null, fragment: null);
}

class ErpApi with _InvoiceApi, _ImportedHistoryApi implements AccessSource {
  ErpApi(Uri uri) : baseUri = validateServer(uri);
  final Uri baseUri;
  final HttpClient _client = HttpClient();
  Cookie? _session;
  String? _localAuthorization;

  void useLocalWorkspace(
    String key,
    String secret, {
    String localAccount = 'local-owner@workspace.example.invalid',
  }) {
    final credential = RegExp(r'^[a-zA-Z0-9_-]{12,128}$');
    if (baseUri.toString() != 'http://127.0.0.1:8081' ||
        !credential.hasMatch(key) ||
        !credential.hasMatch(secret) ||
        !const {
          'local-owner@workspace.example.invalid',
          'local-general-owner@workspace.example.invalid',
        }.contains(localAccount)) {
      throw const ErpException(
        'Local workspace access is unavailable. Run the launcher again.',
      );
    }
    _localAuthorization = 'token $key:$secret';
    // Avoid proxying a local credential to a configured system proxy.
    _client.findProxy = (_) => 'DIRECT';
    userName = 'Local Workspace Owner';
    account = localAccount;
    _session = null;
  }

  /// Only launcher-installed profiles may use this path. Companies are still
  /// authorized by workspaceContext, never by the private launch preferences.
  void useConfiguredLocalWorkspace(
    String key,
    String secret, {
    required String localAccount,
  }) {
    final credential = RegExp(r'^[a-zA-Z0-9_-]{12,128}$');
    if (baseUri.scheme != 'http' ||
        !const {'127.0.0.1', '::1'}.contains(baseUri.host) ||
        !credential.hasMatch(key) ||
        !credential.hasMatch(secret) ||
        localAccount.trim().isEmpty ||
        localAccount.length > 140 ||
        RegExp(r'[\r\n\x00]').hasMatch(localAccount)) {
      throw const ErpException(
        'The configured local workspace is unavailable.',
      );
    }
    _localAuthorization = 'token $key:$secret';
    _client.findProxy = (_) => 'DIRECT';
    userName = 'Workspace account';
    account = localAccount;
    _session = null;
  }

  bool _authenticatingInvite = false;
  String userName = 'Administrator';
  @override
  String account = 'Administrator';
  Future<bool> Function()? onSessionExpired;
  Future<bool>? _sessionRecovery;
  final _accessListeners = <void Function()>{};
  final _contexts = <String, WorkspaceContext>{};
  @override
  int accessRevision = 0;
  @override
  bool accessReady = true;
  bool _refreshingAccess = false;
  void addAccessListener(void Function() listener) =>
      _accessListeners.add(listener);
  void removeAccessListener(void Function() listener) =>
      _accessListeners.remove(listener);
  WorkspaceContext? contextFor(String company) => _contexts[company];
  bool supportsOperationRecovery(String company) =>
      accessReady && (_contexts[company]?.operationRecoveryVersion ?? 0) >= 1;
  void _accessChanged() {
    for (final listener in List.of(_accessListeners)) {
      listener();
    }
  }

  void publishContext(WorkspaceContext value) {
    final previous = _contexts[value.company];
    final changed =
        previous != null &&
        (previous.accessFingerprint != value.accessFingerprint ||
            previous.revision != value.revision ||
            previous.canManageTeam != value.canManageTeam ||
            previous.canReadImportedHistory != value.canReadImportedHistory ||
            previous.knittingOnly != value.knittingOnly ||
            previous.operationRecoveryVersion !=
                value.operationRecoveryVersion ||
            previous.capabilities.toString() != value.capabilities.toString());
    final notify =
        changed || !accessReady || previous == null && accessRevision > 0;
    if (changed) {
      accessRevision++;
      _contexts.clear();
    }
    if (value.company != null) _contexts[value.company!] = value;
    accessReady = true;
    if (notify) _accessChanged();
  }

  static Uri get serviceOrigin {
    const configured = String.fromEnvironment('ERP_SERVER');
    if (configured.isNotEmpty) {
      try {
        return validateServer(Uri.parse(configured));
      } on FormatException {
        throw const ErpException(
          'This app could not connect to its configured service. Contact your workspace manager.',
        );
      }
    }
    if (const bool.fromEnvironment('dart.vm.product')) {
      throw const ErpException(
        'This app needs a configured workspace service. Contact your workspace manager.',
      );
    }
    return validateServer(
      Uri.parse(
        Platform.isAndroid ? 'http://10.0.2.2:8081' : 'http://localhost:8081',
      ),
    );
  }

  static Uri validateServer(Uri uri) => validateServiceOrigin(
    uri,
    isAndroid: Platform.isAndroid,
    isRelease: const bool.fromEnvironment('dart.vm.product'),
    isProfile: const bool.fromEnvironment('dart.vm.profile'),
  );

  Future<void> login(String username, String password) async {
    _session = null;
    final result = await _request(
      '/api/method/login',
      form: {'usr': username, 'pwd': password},
    );
    _finishLogin(username, result);
  }

  Future<void> verifyLogin(
    String username,
    LoginVerification challenge,
    String code,
  ) async {
    final result = await _request(
      '/api/method/login',
      form: {'otp': code.trim(), 'tmp_id': challenge.temporaryId},
    );
    _finishLogin(username, result);
  }

  void _finishLogin(String username, Map<String, dynamic> result) {
    if (result['message'] == 'Password Reset') {
      _session = null;
      throw const ErpException(
        'Use the password reset link in your registered email, then sign in again.',
      );
    }
    final portalLogin = result['message'] == 'No App';
    if (portalLogin && !_authenticatingInvite) {
      _session = null;
      throw const ErpException(
        'This website account can use the ERPNext portal. Ask your workspace manager for a system user account to open ERP Workspace.',
      );
    }
    final verification = result['verification'];
    if (verification is Map && result['message'] != 'Logged In') {
      _session = null;
      final method = verification['method'];
      final id = result['tmp_id'];
      if (id is! String ||
          id.isEmpty ||
          !{'Email', 'SMS', 'OTP App'}.contains(method)) {
        throw const ErpException(
          'Ask your workspace manager to help you sign in with this verification method.',
        );
      }
      if (!enabled(verification['setup'])) {
        throw ErpException(
          method == 'OTP App'
              ? 'Complete authenticator setup with your workspace manager, then sign in again.'
              : 'ERPNext could not send the verification code. Contact your workspace manager, then sign in again.',
        );
      }
      final instructions = verification['prompt'];
      final prompt = instructions is String && instructions.trim().isNotEmpty
          ? plainReportText(instructions).trim()
          : switch (method) {
              'Email' =>
                'Enter the verification code sent to your registered email.',
              'SMS' => 'Enter the verification code sent to your phone.',
              _ => 'Enter the code from your authenticator app.',
            };
      throw LoginVerification(id, prompt);
    }
    if ((result['message'] != 'Logged In' && !portalLogin) ||
        _session == null ||
        _session!.value == 'Guest') {
      throw const ErpException('The username or password was not accepted.');
    }
    userName = result['full_name']?.toString() ?? username;
    account = username;
  }

  Future<Map<String, dynamic>> _request(
    String path, {
    Map<String, String>? query,
    Map<String, String>? form,
  }) async {
    final sessionAtStart = _session?.value;
    final accessAtStart = accessRevision;
    try {
      final uri = baseUri.replace(path: path, queryParameters: query);
      final request = await _client
          .openUrl(form == null ? 'GET' : 'POST', uri)
          .timeout(const Duration(seconds: 20));
      request.followRedirects = false;
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      if (_localAuthorization != null) {
        request.headers.set(
          HttpHeaders.authorizationHeader,
          _localAuthorization!,
        );
      } else if (_session != null) {
        request.cookies.add(_session!);
      }
      if (form != null) {
        request.headers.contentType = ContentType(
          'application',
          'x-www-form-urlencoded',
        );
        request.write(Uri(queryParameters: form).query);
      }
      final response = await request.close().timeout(
        const Duration(seconds: 20),
      );
      final body = await utf8.decoder
          .bind(response)
          .join()
          .timeout(const Duration(seconds: 20));
      Map<String, dynamic>? decoded;
      try {
        final value = jsonDecode(body);
        if (value is Map<String, dynamic>) decoded = value;
      } on FormatException {
        /* Non-JSON errors receive the same safe status handling. */
      }
      var expired =
          response.statusCode == 401 ||
          response.statusCode == 403 &&
              [
                'AuthenticationError',
                'SessionExpired',
              ].contains(decoded?['exc_type']);
      if (response.statusCode == 403 &&
          _session != null &&
          _session!.value != 'Guest' &&
          _session!.value != sessionAtStart) {
        await _expired(path, sessionAtStart);
      }
      if (!expired &&
          response.statusCode == 403 &&
          sessionAtStart != null &&
          path.startsWith('/api/method/erp_extensions.') &&
          !path.endsWith('.session_status')) {
        try {
          final status = await _request(
            '/api/method/erp_extensions.api.session_status',
          );
          expired = (status['message'] as Map?)?['signed_in'] == false;
        } on ErpException catch (e) {
          expired = e.sessionExpired;
        }
      }
      if (expired && _localAuthorization != null) {
        throw const ErpException(
          'Local workspace access needs to be restored. Run the ERP Workspace launcher.',
          sessionExpired: true,
        );
      }
      if (expired && path.endsWith('/login')) {
        if (form?.containsKey('otp') == true) {
          throw const ErpException(
            'Check the verification code. If it has expired, go back and sign in again for a new code.',
          );
        }
        throw const ErpException(
          'Sign-in failed. Check your username and password and try again.',
        );
      }
      if (expired) await _expired(path, sessionAtStart);
      if (response.statusCode == 403) {
        if (!_refreshingAccess &&
            _contexts.isNotEmpty &&
            !path.endsWith('workspace.context') &&
            path.startsWith('/api/method/erp_extensions.')) {
          _refreshingAccess = true;
          try {
            await workspaceContext(company: _contexts.keys.first);
          } catch (_) {
            // A revoked company cannot return a context fingerprint. Hide
            // cached views until each route can validate its current source.
            _contexts.clear();
            accessRevision++;
            accessReady = true;
            _accessChanged();
          } finally {
            _refreshingAccess = false;
          }
        }
        throw const ErpException(
          'This account does not have permission to open this view.',
          permissionDenied: true,
        );
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        if (path.endsWith('/login') &&
            decoded?['exc_type'] == 'ExpiredLoginException') {
          throw const ErpException(
            'This verification code has expired. Go back and sign in again for a new code.',
          );
        }
        if (path.endsWith('/login') && response.statusCode == 429) {
          throw const ErpException(
            'Too many sign-in attempts. Wait a while, then try again.',
          );
        }
        if (path.startsWith('/api/method/erp_extensions.onboarding.') &&
            response.statusCode == 429) {
          throw const ErpException(
            'Too many attempts. Wait a while, then try again.',
          );
        }
        if (decoded?['exc_type'] == 'TimestampMismatchError') {
          throw const ErpException(
            'Someone changed this document. Reload the latest version before saving.',
            staleDocument: true,
          );
        }
        if ([400, 409, 417, 422].contains(response.statusCode)) {
          final message = _validationMessage(decoded);
          if (message != null) {
            throw ErpException(
              message,
              validationRejected: decoded?['exc_type'] == 'ValidationError',
            );
          }
        }
        throw const ErpException(
          'ERPNext could not load this view. Check your connection and try again.',
        );
      }
      if (decoded == null) {
        throw const ErpException('ERPNext returned an unreadable response.');
      }
      for (final cookie in response.cookies) {
        if (_localAuthorization == null &&
            cookie.name == 'sid' &&
            (path.endsWith('/login') || _session?.value == sessionAtStart)) {
          _session = cookie;
        }
      }
      if (accessAtStart != accessRevision && !path.endsWith('/login')) {
        throw const ErpException(
          'Access changed. Reload this view before continuing.',
        );
      }
      return decoded;
    } on HandshakeException {
      throw const ErpException(
        'A secure connection to ERPNext could not be verified. Check the server certificate.',
      );
    } on SocketException {
      throw const ErpException(
        'Cannot reach your workspace. Check your internet connection and try again.',
      );
    } on TimeoutException {
      throw const ErpException(
        'ERPNext took too long to respond. Please try again.',
      );
    } on HttpException {
      throw const ErpException(
        'The connection to ERPNext was interrupted. Please try again.',
      );
    }
  }

  Future<Never> _expired(String path, String? oldSession) async {
    if (_session != null &&
        _session!.value != 'Guest' &&
        _session!.value != oldSession) {
      throw const ErpException(
        'Your session was renewed. Retry your last action.',
      );
    }
    _session = null;
    if (!path.endsWith('/login') && onSessionExpired != null) {
      final existing = _sessionRecovery;
      final companies = List<String>.of(_contexts.keys);
      if (existing == null) {
        accessReady = false;
        accessRevision++;
        _contexts.clear();
        _accessChanged();
      }
      final recovery = existing ?? Future<bool>.sync(onSessionExpired!);
      _sessionRecovery = recovery;
      bool restored = false;
      try {
        restored = await recovery;
      } finally {
        if (identical(_sessionRecovery, recovery)) _sessionRecovery = null;
      }
      if (restored) {
        for (final company in companies) {
          try {
            await workspaceContext(company: company);
          } on ErpException {
            /* Revoked company stays unavailable. */
          }
        }
        accessReady = true;
        _accessChanged();
        throw const ErpException('Signed in again. Retry your last action.');
      }
    }
    throw const ErpException('Please sign in again.', sessionExpired: true);
  }

  static String? _validationMessage(Map<String, dynamic>? response) {
    try {
      final messages = jsonDecode(response?['_server_messages'] as String);
      if (messages is! List || messages.isEmpty) return null;
      final first = messages.first is String
          ? jsonDecode(messages.first)
          : messages.first;
      final message = objectMap(first)['message'];
      if (message is! String || message.trim().isEmpty) return null;
      final text = message
          .replaceAll(RegExp(r'<[^>]*>'), '')
          .replaceAll('&nbsp;', ' ')
          .replaceAll('&amp;', '&');
      return text.length > 700 ? '${text.substring(0, 700)}…' : text;
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>> _native(
    String operation, [
    Map<String, Object?> args = const {},
  ]) async {
    final response = await _request(
      '/api/method/erp_extensions.api.$operation',
      form: {
        for (final entry in args.entries)
          if (entry.value != null)
            entry.key: entry.value is String
                ? entry.value as String
                : jsonEncode(entry.value),
      },
    );
    try {
      return objectMap(response['message']);
    } on FormatException {
      throw const ErpException(
        'ERPNext returned an invalid native-client response.',
      );
    }
  }

  @override
  Future<Map<String, dynamic>> _industry(
    String module,
    String operation,
    Map<String, Object?> args,
  ) async {
    final response = await _request(
      '/api/method/erp_extensions.$module.$operation',
      form: {
        for (final e in args.entries)
          if (e.value != null)
            e.key: e.value is String ? e.value as String : jsonEncode(e.value),
      },
    );
    return objectMap(response['message']);
  }

  Future<void> registerOwner({
    required String fullName,
    required String email,
    required String password,
    required String company,
    required String industry,
  }) async {
    await _industry('onboarding', 'register_owner', {
      'full_name': fullName,
      'email': email,
      'password': password,
      'company': company,
      'industry': industry,
    });
  }

  Future<Map<String, dynamic>> receiptInspectionItems(String receipt) =>
      _industry('operational_handoffs', 'receipt_items', {'receipt': receipt});
  Future<Map<String, dynamic>> inspectReceipt(
    String receipt,
    String row,
    String sample,
    String modified,
  ) => _industry('operational_handoffs', 'inspect_receipt', {
    'receipt': receipt,
    'row': row,
    'sample': sample,
    'modified': modified,
  });
  Future<Map<String, dynamic>> maintenanceLogs(String plan) =>
      _industry('operational_handoffs', 'maintenance_logs', {'plan': plan});
  Future<Map<String, dynamic>> assetMaintenancePlan(String asset) =>
      _industry('operational_handoffs', 'asset_plan', {'asset': asset});

  Future<Map<String, dynamic>> importBankCsv(
    String company,
    String account,
    String stage,
    String content,
    Map<String, String> mapping,
    String format,
  ) => _industry('bank_csv', 'statement_csv', {
    'company': company,
    'bank_account': account,
    'stage': stage,
    'content': content,
    'mapping': mapping,
    'date_format': format,
  });

  Future<Map<String, dynamic>> bankStatements(
    String company,
    String account,
    String query,
  ) => _industry('bank_matching', 'entries', {
    'company': company,
    'bank_account': account,
    'query': query,
  });
  Future<Map<String, dynamic>> bankMatches(
    String company,
    String account,
    String statement, {
    String from = '',
    String to = '',
  }) => _industry('bank_matching', 'matches', {
    'company': company,
    'bank_account': account,
    'statement': statement,
    'from_date': from,
    'to_date': to,
  });
  Future<Map<String, dynamic>> matchBankPayment(
    String company,
    String account,
    String statement,
    String payment,
    String expectedStatement,
    String expectedPayment, {
    String from = '',
    String to = '',
  }) => _industry('bank_matching', 'match', {
    'company': company,
    'bank_account': account,
    'statement': statement,
    'payment': payment,
    'expected_statement': expectedStatement,
    'expected_payment': expectedPayment,
    'from_date': from,
    'to_date': to,
  });

  Future<Map<String, dynamic>> reconciliationEntries(
    String company,
    String partyType,
    String party, {
    String paymentQuery = '',
    String invoiceQuery = '',
  }) => _industry('reconciliation', 'candidates', {
    'company': company,
    'party_type': partyType,
    'party': party,
    'payment_query': paymentQuery,
    'invoice_query': invoiceQuery,
  });

  Future<Map<String, dynamic>> beginOperation(
    String company,
    String kind,
    String requestId, {
    String? doctype,
    String? name,
    String? action,
  }) => _industry('operations', 'begin_operation', {
    'company': company,
    'kind': kind,
    'request_id': requestId,
    'doctype': doctype,
    'name': name,
    'action': action,
  });

  Future<Map<String, dynamic>> pendingOperations(
    String company, {
    int start = 0,
  }) => _industry('operations', 'pending_operations', {
    'company': company,
    'start': start,
  });

  Future<Map<String, dynamic>> operationStatus(
    String company,
    String requestId,
  ) => _industry('operations', 'operation_status', {
    'company': company,
    'request_id': requestId,
  });

  Future<Map<String, dynamic>> closeOperation(
    String company,
    String requestId,
  ) => _industry('operations', 'close_operation', {
    'company': company,
    'request_id': requestId,
  });

  Future<void> acknowledgeOperation(String company, String requestId) async {
    await _industry('operations', 'acknowledge_operation', {
      'company': company,
      'request_id': requestId,
    });
  }

  Future<Map<String, dynamic>> allocatePayment(
    String company,
    String partyType,
    String party, {
    required String payment,
    required String invoice,
    required String amount,
    required String expectedPayment,
    required String expectedInvoice,
    String? requestId,
  }) => _industry('reconciliation', 'allocate', {
    'company': company,
    'party_type': partyType,
    'party': party,
    'payment': payment,
    'invoice': invoice,
    'amount': amount,
    'expected_payment': expectedPayment,
    'expected_invoice': expectedInvoice,
    'request_id': requestId,
  });

  Future<void> redeemExistingInvitation(
    String token,
    Future<void> Function() authenticate,
  ) async {
    // A portal account must prove its identity before it can redeem a staff invitation.
    _authenticatingInvite = true;
    try {
      await authenticate();
      await acceptInvitation(token);
    } finally {
      _authenticatingInvite = false;
      if (_session != null && _session!.value != 'Guest') {
        try {
          await signOut();
        } on ErpException {
          // Changing the Frappe user type can already have revoked this session.
        }
      }
    }
  }

  Future<void> acceptInvitation(
    String token, {
    String? fullName,
    String? email,
    String? password,
  }) async {
    await _industry('onboarding', 'accept_invite', {
      'token': token,
      'full_name': fullName,
      'email': email,
      'password': password,
    });
  }

  Future<Map<String, dynamic>> team(String company) =>
      _industry('onboarding', 'team', {'company': company});

  Future<Map<String, dynamic>> inviteMember(
    String company,
    String email,
    String role,
  ) => _industry('onboarding', 'invite_member', {
    'company': company,
    'email': email,
    'role': role,
  });

  Future<void> revokeInvitation(String company, String name) async {
    await _industry('onboarding', 'revoke_invite', {
      'company': company,
      'name': name,
    });
  }

  Future<Map<String, dynamic>> posConfigure(String company) =>
      _industry('pos_checkout', 'configure', {'company': company});

  Future<Map<String, dynamic>> posRegister(String company) =>
      _industry('pos_checkout', 'register', {'company': company});

  Future<Map<String, dynamic>> posOpenShift(
    String company,
    String profile,
    String amount,
  ) => _industry('pos_checkout', 'open_shift', {
    'company': company,
    'profile': profile,
    'amount': amount,
  });

  Future<Map<String, dynamic>> posQuote(
    String company,
    String opening,
    String customer,
    List<Map<String, dynamic>> items,
  ) => _industry('pos_checkout', 'quote', {
    'company': company,
    'opening': opening,
    'customer': customer,
    'items': items,
  });

  Future<Map<String, dynamic>> posCheckout(
    String company,
    String opening,
    String customer,
    List<Map<String, dynamic>> items,
    String expected,
    String token,
  ) => _industry('pos_checkout', 'checkout', {
    'company': company,
    'opening': opening,
    'customer': customer,
    'items': items,
    'expected': expected,
    'token': token,
  });

  Future<Map<String, dynamic>> posRefundReview(
    String company,
    String opening,
    String invoice,
  ) => _industry('pos_checkout', 'refund_review', {
    'company': company,
    'opening': opening,
    'invoice': invoice,
  });

  Future<Map<String, dynamic>> posRefund(
    String company,
    String opening,
    String invoice,
    String expected,
    String token,
  ) => _industry('pos_checkout', 'refund', {
    'company': company,
    'opening': opening,
    'invoice': invoice,
    'expected': expected,
    'token': token,
  });

  Future<Map<String, dynamic>> posClosing(String company, String opening) =>
      _industry('pos_checkout', 'closing', {
        'company': company,
        'opening': opening,
      });

  Future<Map<String, dynamic>> posCloseShift(
    String company,
    String opening,
    Map<String, String> amounts,
    String revision,
  ) => _industry('pos_checkout', 'close_shift', {
    'company': company,
    'opening': opening,
    'amounts': amounts,
    'revision': revision,
  });

  Future<WorkspaceContext> workspaceContext({String? company}) async {
    final value = WorkspaceContext.fromJson(
      await _industry('workspace', 'context', {'company': company}),
    );
    publishContext(value);
    return value;
  }

  Future<WorkspaceContext> selectCompany(String company) async {
    final value = WorkspaceContext.fromJson(
      await _industry('workspace', 'select_company', {'company': company}),
    );
    publishContext(value);
    return value;
  }

  Future<WorkspaceContext> configureIndustry(
    String company,
    Map<String, dynamic> settings,
  ) async {
    final context = WorkspaceContext.fromJson(
      await _industry('workspace', 'configure', {
        'company': company,
        'settings': settings,
      }),
    );
    publishContext(context);
    return context;
  }

  Future<Map<String, dynamic>> industrySettings(String company) =>
      _industry('workspace', 'settings', {'company': company});
  Future<KnittingSnapshot> knittingSnapshot(
    String company, {
    String? job,
  }) async => KnittingSnapshot.fromJson(
    await _industry('knitting.api', 'snapshot', {
      'company': company,
      'job': job,
    }),
  );
  Future<Map<String, dynamic>> knittingRegister(
    String company,
    String collection, {
    String? job,
    int start = 0,
    String query = '',
    String? state,
    String? productionDate,
    String? fromDate,
    String? toDate,
    String? customer,
    String? category,
  }) => _industry('knitting.api', 'register', {
    'company': company,
    'collection': collection,
    'job': ?job,
    'start': start,
    'query': query,
    'state': ?state,
    'production_date': ?productionDate,
    'from_date': ?fromDate,
    'to_date': ?toDate,
    'customer': ?customer,
    'category': ?category,
  });
  Future<Map<String, dynamic>> knittingOverview(String company) =>
      _industry('knitting.api', 'overview', {'company': company});
  Future<Map<String, dynamic>> knittingRoll(
    String company,
    String job,
    String roll,
  ) => _industry('knitting.api', 'roll', {
    'company': company,
    'job': job,
    'roll': roll,
  });
  Future<Map<String, dynamic>> knittingCommand(
    String company,
    String action,
    Map<String, dynamic> values,
    String requestId, {
    String? modified,
  }) => _industry('knitting.api', 'command', {
    'company': company,
    'action': action,
    'payload': values,
    'request_id': requestId,
    'modified': modified,
  });
  Future<Map<String, dynamic>> knittingInvoicePreview(
    String company,
    Map<String, dynamic> values,
    String? modified,
  ) => _industry('knitting.api', 'invoice_preview', {
    'company': company,
    'payload': values,
    'modified': modified,
  });
  Future<Map<String, dynamic>> knittingCommandStatus(
    String company,
    String requestId,
  ) => _industry('knitting.api', 'command_status', {
    'company': company,
    'request_id': requestId,
  });
  Future<Map<String, dynamic>> knittingLookup(
    String company,
    String entity,
    String query, {
    int start = 0,
    String? job,
  }) => _industry('knitting.api', 'lookup', {
    'company': company,
    'entity': entity,
    'query': query,
    'start': start,
    'job': ?job,
  });
  Future<Map<String, dynamic>> knittingReport(
    String company,
    String report,
    Map<String, dynamic> filters,
  ) => _industry('knitting.api', 'report', {
    'company': company,
    'report': report,
    'filters': filters,
  });
  Future<Map<String, dynamic>> knittingExport(
    String company,
    String format,
    Map<String, dynamic> filters,
  ) => _industry('knitting.api', 'export', {
    'company': company,
    'format': format,
    'filters': filters,
  });

  Future<Map<String, dynamic>> documentActivity(String type, String name) =>
      _native('activity', {'doctype': type, 'name': name});
  Future<void> comment(String type, String name, String content) async {
    await _native('add_comment', {
      'doctype': type,
      'name': name,
      'content': content,
    });
  }

  Future<void> assignDocument(String type, String name, String user) async {
    await _native('assign', {'doctype': type, 'name': name, 'user': user});
  }

  Future<void> unassignDocument(String type, String name, String user) async {
    await _native('unassign', {'doctype': type, 'name': name, 'user': user});
  }

  Future<void> uploadAttachment(
    String type,
    String name,
    String filename,
    Uint8List bytes,
  ) async {
    await _native('upload_attachment', {
      'doctype': type,
      'name': name,
      'filename': filename,
      'content': base64Encode(bytes),
    });
  }

  Future<({String name, Uint8List bytes})> fieldAttachment(
    String type,
    String name,
    String field, {
    String? table,
    String? row,
  }) async {
    final result = await _native('field_attachment', {
      'doctype': type,
      'name': name,
      'field': field,
      'table': table,
      'row': row,
    });
    return (
      name: result['name'] as String,
      bytes: base64Decode(result['content'] as String),
    );
  }

  Future<void> removeAttachment(String type, String name, String file) async {
    await _native('remove_attachment', {
      'doctype': type,
      'name': name,
      'file': file,
    });
  }

  Future<({String name, Uint8List bytes})> attachment(
    String type,
    String name,
    String file,
  ) async {
    final result = await _native('attachment', {
      'doctype': type,
      'name': name,
      'file': file,
    });
    return (
      name: result['name'] as String,
      bytes: base64Decode(result['content'] as String),
    );
  }

  Future<List<String>> printOptions(String type, String name) async =>
      List<String>.from(
        (await _native('print_options', {
              'doctype': type,
              'name': name,
            }))['formats']
            as List,
      );
  Future<({String name, Uint8List bytes})> printPdf(
    String type,
    String name,
    String format,
  ) async {
    final result = await _native('print_pdf', {
      'doctype': type,
      'name': name,
      'format': format,
    });
    return (
      name: result['name'] as String,
      bytes: base64Decode(result['content'] as String),
    );
  }

  Future<NativeCatalog> nativeCatalog({String? company}) async =>
      NativeCatalog.fromJson(await _native('catalog', {'company': company}));

  Future<Map<String, dynamic>> reportDefinition(
    String name, {
    String? company,
  }) => _native('report_definition', {'name': name, 'company': company});
  Future<NativeReportResult> runReport(
    String name,
    Map<String, dynamic> filters,
  ) async => NativeReportResult.fromJson(
    await _native('run_report', {'name': name, 'filters': filters}),
  );
  Future<void> queueReport(String name, Map<String, dynamic> filters) async {
    await _native('queue_report', {'name': name, 'filters': filters});
  }

  Future<int> reclassifyMasters(
    String doctype,
    String company,
    List<Map<String, String>> records,
    String group,
  ) async {
    final result = await _native('reclassify_masters', {
      'doctype': doctype,
      'company': company,
      'records': records,
      'group': group,
    });
    return result['count'] as int;
  }

  Future<Map<String, dynamic>> importMasters(
    String doctype,
    String company,
    String stage, {
    String? content,
  }) => _native('import_masters', {
    'doctype': doctype,
    'company': company,
    'stage': stage,
    'content': content,
  });

  Future<void> changeTreeRecord(
    String doctype,
    String name,
    String modified,
    String action, {
    String? company,
    String? newName,
  }) async {
    await _native('change_tree_record', {
      'doctype': doctype,
      'name': name,
      'modified': modified,
      'action': action,
      'company': company,
      'new_name': ?newName,
    });
  }

  Future<NativeSchema> nativeSchema(String doctype) async =>
      NativeSchema.fromJson(await _native('schema', {'doctype': doctype}));
  Future<Map<String, dynamic>> nativeTree(
    String doctype, {
    String? parent,
    String? company,
    int start = 0,
  }) async {
    final result = await _native('tree_children', {
      'doctype': doctype,
      'parent': parent,
      'company': company,
      'start': start,
    });
    final nodes = result['nodes'];
    if (nodes is! List ||
        result['has_more'] is! bool ||
        result['can_create'] is! bool ||
        nodes.any(
          (row) =>
              row is! Map ||
              row['name'] is! String ||
              (row['name'] as String).isEmpty ||
              row['title'] is! String ||
              row['expandable'] is! bool,
        )) {
      throw const ErpException(
        'ERPNext returned an invalid hierarchy. Refresh and try again.',
      );
    }
    return result;
  }

  Future<NativeDocument> nativeDocument(
    String doctype, {
    String? name,
    String? company,
    String? treeParent,
  }) async => NativeDocument.fromJson(
    await _native('document', {
      'doctype': doctype,
      'name': name,
      'company': company,
      'tree_parent': treeParent,
    }),
  );
  Future<NativeDocument> saveNative(
    NativeSchema schema,
    Map<String, dynamic> document, {
    String action = 'Save',
    String? requestId,
    String? company,
  }) async => NativeDocument.fromJson(
    await _native('save', {
      'document': schema.payload(document),
      'action': action,
      'request_id': requestId,
      'company': company,
    }),
  );
  Future<NativeDocument> partyDefaultsNative(
    NativeSchema schema,
    Map<String, dynamic> document,
  ) async => NativeDocument.fromJson(
    await _native('party_defaults', {'document': schema.payload(document)}),
  );
  Future<Map<String, dynamic>> itemDefaultsNative(
    NativeSchema schema,
    Map<String, dynamic> document,
    NativeField field,
    Map<String, dynamic> row,
  ) async => objectMap(
    (await _native('item_defaults', {
      'document': schema.payload(document),
      'field': field.name,
      'row': schema.children[field.options]!.payload(row),
    }))['doc'],
  );
  Future<NativeDocument> newFromNative(
    String type,
    String name,
    String action,
    String modified, {
    num? quantity,
  }) async => NativeDocument.fromJson(
    await _native('new_from', {
      'doctype': type,
      'name': name,
      'action': action,
      'modified': modified,
      'quantity': quantity,
    }),
  );
  Future<NativeDocument> prepareNative(
    NativeSchema schema,
    Map<String, dynamic> document,
  ) async => NativeDocument.fromJson(
    await _native('prepare', {'document': schema.payload(document)}),
  );
  Future<NativeDocument> transitionNative(
    String doctype,
    String name,
    String action, {
    required String modified,
    String? requestId,
    String? company,
  }) async => NativeDocument.fromJson(
    await _native('transition', {
      'doctype': doctype,
      'name': name,
      'action': action,
      'modified': modified,
      'request_id': requestId,
      'company': company,
    }),
  );

  Future<Map<String, dynamic>> taskView(
    String company, {
    String? month,
    String? status,
    int start = 0,
  }) => _native('task_view', {
    'company': company,
    'month': ?month,
    'status': ?status,
    'start': start,
  });

  Future<List<Map<String, dynamic>>> nativeRecords(
    String doctype, {
    String query = '',
    int start = 0,
    String? company,
  }) async {
    final result = await _request(
      '/api/method/erp_extensions.api.records',
      form: {
        'doctype': doctype,
        'query': query,
        'start': '$start',
        'company': ?company,
      },
    );
    final rows = result['message'];
    if (rows is! List) {
      throw const ErpException('ERPNext returned an invalid record list.');
    }
    return rows.map(objectMap).toList();
  }

  Future<List<Map<String, dynamic>>> searchLinks(
    String doctype,
    String query, {
    String? parent,
    String? field,
    Map<String, String>? contextValues,
  }) async {
    final result = await _request(
      '/api/method/erp_extensions.api.search_link',
      form: {
        'doctype': doctype,
        'query': query,
        'parent': ?parent,
        'field': ?field,
        if (contextValues != null) 'context': jsonEncode(contextValues),
      },
    );
    final rows = result['message'];
    if (rows is! List) {
      throw const ErpException('ERPNext returned invalid linked records.');
    }
    return rows.map(objectMap).toList();
  }

  Future<List<Map<String, dynamic>>> _list(
    String doctype,
    List<Object> fields, {
    List<List<dynamic>> filters = const [],
    String? groupBy,
    String? orderBy,
    int limit = 50,
    int start = 0,
    List<List<dynamic>>? orFilters,
  }) async {
    final response = await _request(
      '/api/method/frappe.client.get_list',
      query: {
        'doctype': doctype,
        'fields': jsonEncode(fields),
        'filters': jsonEncode(filters),
        'limit_page_length': '$limit',
        'limit_start': '$start',
        'group_by': ?groupBy,
        'order_by': ?orderBy,
        if (orFilters != null) 'or_filters': jsonEncode(orFilters),
      },
    );
    final rows = response['message'];
    if (rows is! List || rows.any((e) => e is! Map<String, dynamic>)) {
      throw const ErpException('ERPNext returned an unexpected record list.');
    }
    return rows.cast<Map<String, dynamic>>();
  }

  Future<int> _count(String doctype, List<List<dynamic>> filters) async {
    final response = await _request(
      '/api/method/frappe.client.get_count',
      query: {'doctype': doctype, 'filters': jsonEncode(filters)},
    );
    final value = response['message'];
    if (value is! num || !value.isFinite || value < 0) {
      throw const ErpException('ERPNext returned an unexpected count.');
    }
    return value.toInt();
  }

  Future<List<ErpRecord>> records(
    ErpModule module, {
    required String company,
    ReportingPeriod period = ReportingPeriod.month,
    DateTime? now,
    String query = '',
    int start = 0,
    int limit = 50,
    bool unpaidOnly = false,
  }) async {
    final search = query.trim();
    final rows = await _list(
      module.doctype,
      module.fields,
      filters: [
        ...module.filters(company, period.range(now ?? DateTime.now())),
        if (unpaidOnly && module == ErpModule.accounts) ...[
          ['docstatus', '=', 1],
          ['outstanding_amount', '>', 0],
        ],
      ],
      orderBy: 'modified desc',
      start: start,
      limit: limit,
      orFilters: search.isEmpty
          ? null
          : [
              ['name', 'like', '%$search%'],
              [module.titleField, 'like', '%$search%'],
            ],
    );
    if (rows.any(
      (r) => r['name'] is! String || (r['name'] as String).isEmpty,
    )) {
      throw const ErpException(
        'ERPNext returned a record without an identifier.',
      );
    }
    try {
      final result = rows.map((r) => ErpRecord(r, module)).toList();
      for (final record in result) {
        record
            .amount; // Validate before the Future completes and the UI renders.
      }
      return result;
    } on FormatException {
      throw const ErpException('ERPNext returned an invalid amount.');
    }
  }

  Future<T?> _permitted<T>(Future<T> Function() read) async {
    try {
      return await read();
    } on ErpException catch (e) {
      if (e.permissionDenied) return null;
      rethrow;
    }
  }

  Future<Map<String, dynamic>> newRowNative(
    NativeSchema schema,
    Map<String, dynamic> document,
    String field,
  ) async => objectMap(
    (await _native('new_row', {
      'document': schema.payload(document),
      'field': field,
    }))['doc'],
  );

  Future<ErpSnapshot> snapshot(
    ReportingPeriod period, {
    String? selectedCompany,
  }) async {
    try {
      final companies = await _list(
        'Company',
        ['name', 'default_currency'],
        filters: selectedCompany == null
            ? []
            : [
                ['name', '=', selectedCompany],
              ],
        orderBy: 'name asc',
      );
      if (companies.isEmpty) {
        throw const ErpException('Create a company in ERPNext to get started.');
      }
      final company = companies.first;
      if (selectedCompany != null && company['name'] != selectedCompany) {
        throw const ErpException(
          'This company is unavailable. Choose an authorised company.',
        );
      }
      if (company['name'] is! String ||
          company['default_currency'] is! String) {
        throw const ErpException(
          'The company details are incomplete in ERPNext.',
        );
      }
      final name = company['name'] as String;
      final range = period.range(DateTime.now());
      final counts = <ErpModule, int?>{};
      final masters = <String, int?>{};
      await Future.wait([
        for (final module in ErpModule.values)
          _permitted(() => _count(module.doctype, module.filters(name, range)))
              .then((n) => counts[module] = n),
        for (final type in ['Customer', 'Supplier', 'Warehouse'])
          _permitted(
            () => _count(
              type,
              type == 'Warehouse'
                  ? [
                      ['company', '=', name],
                    ]
                  : [],
            ),
          ).then((n) => masters[type] = n),
      ]);
      final financialFilters = [
        ...ErpModule.accounts.filters(name, range),
        ['docstatus', '=', 1],
      ];
      double? billed;
      int? unpaidInvoices;
      var sales = <SalesDay>[];
      var activity = <ErpRecord>[];
      if (counts[ErpModule.accounts] != null) {
        try {
          final totals = await _list(
            'Sales Invoice',
            [
              {'SUM': 'base_grand_total', 'as': 'billed'},
            ],
            filters: financialFilters,
            limit: 1,
          );
          if (totals.length != 1 || !totals.first.containsKey('billed')) {
            throw const ErpException(
              'ERPNext returned incomplete financial totals.',
            );
          }
          final days = await _list(
            'Sales Invoice',
            [
              'posting_date',
              {'SUM': 'base_grand_total', 'as': 'amount'},
            ],
            filters: financialFilters,
            groupBy: 'posting_date',
            orderBy: 'posting_date asc',
            limit: 366,
          );
          final recent = await records(
            ErpModule.accounts,
            company: name,
            period: period,
            limit: 4,
          );
          final unpaid = await _count('Sales Invoice', [
            ...financialFilters,
            ['outstanding_amount', '>', 0],
          ]);
          final dailySales = days
              .map(
                (d) => SalesDay(
                  DateTime.parse(d['posting_date']),
                  number(d['amount']),
                ),
              )
              .toList();
          billed = number(totals.first['billed']);
          unpaidInvoices = unpaid;
          sales = dailySales;
          activity = recent;
        } on ErpException catch (e) {
          if (!e.permissionDenied) rethrow;
          counts[ErpModule.accounts] = null;
        }
      }
      return ErpSnapshot(
        company: name,
        currency: company['default_currency'],
        counts: counts,
        customers: masters['Customer'],
        suppliers: masters['Supplier'],
        warehouses: masters['Warehouse'],
        billed: billed,
        unpaidInvoices: unpaidInvoices,
        sales: sales,
        activity: activity,
      );
    } on FormatException {
      throw const ErpException('ERPNext returned an invalid date or amount.');
    }
  }

  Future<void> signOut() async {
    try {
      await _request('/api/method/logout', form: const {});
    } finally {
      _session = null;
    }
  }

  void close() => _client.close(force: true);
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'erp_models.dart';
import 'native_models.dart';
import 'native_reports.dart';
import 'workspace_context.dart';
import 'knitting_models.dart';

class ErpException implements Exception {
  const ErpException(
    this.message, {
    this.sessionExpired = false,
    this.permissionDenied = false,
  });
  final String message;
  final bool sessionExpired;
  final bool permissionDenied;
  @override
  String toString() => message;
}

class ErpApi {
  ErpApi(Uri uri) : baseUri = validateServer(uri);
  final Uri baseUri;
  final HttpClient _client = HttpClient();
  Cookie? _session;
  String userName = 'Administrator';
  String account = 'Administrator';
  Future<bool> Function()? onSessionExpired;
  Future<bool>? _sessionRecovery;

  static Uri validateServer(Uri uri) {
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
        'Enter an HTTPS server address, or a local development address.',
      );
    }
    return uri.replace(path: '', query: null, fragment: null);
  }

  Future<void> login(String username, String password) async {
    final result = await _request(
      '/api/method/login',
      form: {'usr': username, 'pwd': password},
    );
    if (result['message'] != 'Logged In' ||
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
    try {
      final uri = baseUri.replace(path: path, queryParameters: query);
      final request = await _client
          .openUrl(form == null ? 'GET' : 'POST', uri)
          .timeout(const Duration(seconds: 20));
      request.followRedirects = false;
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      if (_session != null) request.cookies.add(_session!);
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
      if (expired) await _expired(path, sessionAtStart);
      if (response.statusCode == 403) {
        throw const ErpException(
          'This account does not have permission to open this view.',
          permissionDenied: true,
        );
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        if ([400, 409, 417, 422].contains(response.statusCode)) {
          final message = _validationMessage(decoded);
          if (message != null) throw ErpException(message);
        }
        throw const ErpException(
          'ERPNext could not load this view. Check your connection and try again.',
        );
      }
      if (decoded == null) {
        throw const ErpException('ERPNext returned an unreadable response.');
      }
      for (final cookie in response.cookies) {
        if (cookie.name == 'sid' &&
            (path.endsWith('/login') || _session?.value == sessionAtStart)) {
          _session = cookie;
        }
      }
      return decoded;
    } on HandshakeException {
      throw const ErpException(
        'A secure connection to ERPNext could not be verified. Check the server certificate.',
      );
    } on SocketException {
      throw const ErpException(
        'Cannot reach ERPNext. Check the server address and that the local services are running.',
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
      final recovery = existing ?? Future<bool>.sync(onSessionExpired!);
      _sessionRecovery = recovery;
      bool restored = false;
      try {
        restored = await recovery;
      } finally {
        if (identical(_sessionRecovery, recovery)) _sessionRecovery = null;
      }
      if (restored) {
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

  Future<WorkspaceContext> workspaceContext({String? company}) async =>
      WorkspaceContext.fromJson(
        await _industry('workspace', 'context', {'company': company}),
      );
  Future<WorkspaceContext> configureIndustry(
    String company,
    Map<String, dynamic> settings,
  ) async => WorkspaceContext.fromJson(
    await _industry('workspace', 'configure', {
      'company': company,
      'settings': settings,
    }),
  );
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
  }) => _industry('knitting.api', 'lookup', {
    'company': company,
    'entity': entity,
    'query': query,
    'start': start,
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
  }) async => NativeDocument.fromJson(
    await _native('save', {
      'document': schema.payload(document),
      'action': action,
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
    String modified,
  ) async => NativeDocument.fromJson(
    await _native('new_from', {
      'doctype': type,
      'name': name,
      'action': action,
      'modified': modified,
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
  }) async => NativeDocument.fromJson(
    await _native('transition', {
      'doctype': doctype,
      'name': name,
      'action': action,
      'modified': modified,
    }),
  );

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
  }) async {
    final result = await _request(
      '/api/method/erp_extensions.api.search_link',
      form: {
        'doctype': doctype,
        'query': query,
        'parent': ?parent,
        'field': ?field,
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
  }) async {
    final search = query.trim();
    final rows = await _list(
      module.doctype,
      module.fields,
      filters: module.filters(company, period.range(now ?? DateTime.now())),
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
      final companies = await _list('Company', [
        'name',
        'default_currency',
      ], orderBy: 'name asc');
      if (companies.isEmpty) {
        throw const ErpException('Create a company in ERPNext to get started.');
      }
      final company = companies.firstWhere(
        (c) => c['name'] == selectedCompany,
        orElse: () => companies.first,
      );
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
          _permitted(
            () => _count(module.doctype, module.filters(name, range)),
          ).then((n) => counts[module] = n),
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

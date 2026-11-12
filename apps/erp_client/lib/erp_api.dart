import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'erp_models.dart';

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
  }

  Future<Map<String, dynamic>> _request(
    String path, {
    Map<String, String>? query,
    Map<String, String>? form,
  }) async {
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
      if (response.statusCode == 401 ||
          response.statusCode == 403 &&
              [
                'AuthenticationError',
                'SessionExpired',
              ].contains(decoded?['exc_type'])) {
        _session = null;
        throw const ErpException('Please sign in again.', sessionExpired: true);
      }
      if (response.statusCode == 403) {
        throw const ErpException(
          'This account does not have permission to open this view.',
          permissionDenied: true,
        );
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw const ErpException(
          'ERPNext could not load this view. Check your connection and try again.',
        );
      }
      if (decoded == null) {
        throw const ErpException('ERPNext returned an unreadable response.');
      }
      for (final cookie in response.cookies) {
        if (cookie.name == 'sid') _session = cookie;
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

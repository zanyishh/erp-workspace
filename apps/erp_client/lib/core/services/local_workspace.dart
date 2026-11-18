import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

import '../../erp_api.dart';

/// A credential installed by the local Mac launcher, never bundled in an app.
class LocalWorkspace {
  const LocalWorkspace(
    this.api,
    this.company, {
    this.companies = const [],
    this.profiles = const [],
    this.workspaceId,
    this.workspaceLabel,
  });
  final ErpApi api;
  final String company;
  final List<Map<String, String>> companies;
  final List<Map<String, String>> profiles;
  final String? workspaceId, workspaceLabel;

  static const _configuredOrigin = String.fromEnvironment('ERP_SERVER');
  static bool get enabled {
    if (!Platform.isMacOS) return false;
    const useLocal = bool.fromEnvironment(
      'ERP_LOCAL_WORKSPACE',
      defaultValue: kDebugMode,
    );
    final origin = Uri.tryParse(_configuredOrigin);
    return useLocal &&
        (_configuredOrigin.isEmpty || origin != null && _loopback(origin));
  }

  static bool _loopback(Uri uri) =>
      uri.scheme == 'http' &&
      const {'127.0.0.1', '::1'}.contains(uri.host) &&
      uri.userInfo.isEmpty &&
      !uri.hasQuery &&
      !uri.hasFragment &&
      (uri.path.isEmpty || uri.path == '/');

  static Future<LocalWorkspace> open({
    String? company,
    String? workspaceId,
  }) async {
    final origin = _configuredOrigin.isEmpty
        ? Uri.parse('http://127.0.0.1:8081')
        : ErpApi.serviceOrigin;
    if (!Platform.isMacOS) {
      throw const ErpException(
        'This local build requires the isolated workspace on this Mac.',
      );
    }
    try {
      final support = await const MethodChannel('org.localerp.workspace/local')
          .invokeMethod<String>('applicationSupport');
      if (support == null || !support.startsWith('/')) {
        throw const FormatException();
      }
      const generalOnly = bool.fromEnvironment('ERP_GENERAL_LOCAL_PROFILE');
      final file = File(
        '$support/ERP Workspace/${generalOnly ? 'general-launch.json' : 'local-launch.json'}',
      );
      final saved = jsonDecode(await file.readAsString());
      if (generalOnly) {
        final profiles = saved is Map ? saved['workspaces'] : null;
        if (profiles is! List ||
            profiles.length != 1 ||
            profiles.first is! Map ||
            profiles.first['id'] != 'demo-general' ||
            profiles.first['site'] != 'native-test.localhost' ||
            profiles.first['origin'] != 'http://127.0.0.1:8081' ||
            (company != null && company != profiles.first['company']) ||
            profiles.first['account'] !=
                'local-general-owner@workspace.example.invalid') {
          throw const FormatException();
        }
      }
      if (saved is Map && saved['version'] == 2) {
        return _configured(saved, company: company, workspaceId: workspaceId);
      }
      if (saved is! Map || saved['site'] != 'native-test.localhost') {
        throw const FormatException();
      }
      if (origin.toString() != 'http://127.0.0.1:8081' || workspaceId != null) {
        throw const FormatException();
      }
      final entries = saved['workspaces'] ?? [saved];
      if (entries is! List || entries.isEmpty || entries.length > 2) {
        throw const FormatException();
      }
      const accounts = {
        'Meridian Trading': 'local-general-owner@workspace.example.invalid',
        'Kaveri Loomworks': 'local-owner@workspace.example.invalid',
      };
      final companies = <Map<String, String>>[];
      Map? access;
      final selected = company ?? saved['company'];
      for (final entry in entries) {
        if (entry is! Map ||
            entry['site'] != 'native-test.localhost' ||
            !accounts.containsKey(entry['company']) ||
            accounts[entry['company']] != entry['account'] ||
            entry['key'] is! String ||
            entry['secret'] is! String ||
            companies.any((row) => row['name'] == entry['company'])) {
          throw const FormatException();
        }
        companies.add({
          'name': entry['company'],
          'industry': entry['company'] == 'Meridian Trading'
              ? 'general'
              : 'knitting',
        });
        if (entry['company'] == selected) access = entry;
      }
      if (access == null) throw const FormatException();
      final api = ErpApi(origin);
      try {
        api.useLocalWorkspace(
          access['key'],
          access['secret'],
          localAccount: access['account'],
        );
        return LocalWorkspace(
          api,
          access['company'],
          companies: List.unmodifiable(companies),
        );
      } catch (_) {
        api.close();
        rethrow;
      }
    } on FileSystemException {
      throw const ErpException(
        'Run the ERP Workspace launcher once to prepare this Mac.',
      );
    } on FormatException {
      throw const ErpException(
        'Run the ERP Workspace launcher to restore local workspace access.',
      );
    }
  }

  static LocalWorkspace _configured(
    Map saved, {
    String? company,
    String? workspaceId,
  }) {
    final entries = saved['workspaces'];
    if (entries is! List || entries.isEmpty || entries.length > 20) {
      throw const FormatException();
    }
    final selected = workspaceId ?? saved['selected_workspace'];
    final profiles = <Map<String, String>>[];
    Map? access;
    final ids = <String>{};
    for (final entry in entries) {
      if (entry is! Map ||
          entry['id'] is! String ||
          !RegExp(r'^[a-zA-Z0-9_-]{1,64}$').hasMatch(entry['id']) ||
          !ids.add(entry['id']) ||
          entry['label'] is! String ||
          (entry['label'] as String).trim().isEmpty ||
          entry['site'] is! String ||
          !RegExp(r'^[a-zA-Z0-9][a-zA-Z0-9.-]*\.localhost$')
              .hasMatch(entry['site']) ||
          entry['origin'] is! String ||
          !_loopback(Uri.parse(entry['origin'])) ||
          entry['company'] is! String ||
          (entry['company'] as String).trim().isEmpty ||
          entry['account'] is! String ||
          entry['key'] is! String ||
          entry['secret'] is! String) {
        throw const FormatException();
      }
      profiles.add({'id': entry['id'], 'label': entry['label']});
      if (entry['id'] == selected) access = entry;
    }
    if (access == null) throw const FormatException();
    final api = ErpApi(Uri.parse(access['origin']));
    try {
      api.useConfiguredLocalWorkspace(
        access['key'],
        access['secret'],
        localAccount: access['account'],
      );
      return LocalWorkspace(
        api,
        company ?? access['company'],
        workspaceId: access['id'],
        workspaceLabel: access['label'],
        profiles: List.unmodifiable(profiles),
      );
    } catch (_) {
      api.close();
      rethrow;
    }
  }
}

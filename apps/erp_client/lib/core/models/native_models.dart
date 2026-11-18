import 'dart:convert';

import 'native_conditions.dart';
import 'native_barcode.dart';

bool enabled(Object? value) => value == true || value == 1 || value == '1';
Map<String, dynamic> objectMap(Object? value) {
  if (value is! Map<String, dynamic>) {
    throw const FormatException('Expected an object from ERPNext.');
  }
  return value;
}

class NativeField {
  NativeField.fromJson(Map<String, dynamic> json)
    : name = json['fieldname'] as String,
      label = (json['label'] ?? json['fieldname']) as String,
      type = json['fieldtype'] as String,
      options = json['options']?.toString() ?? '',
      required = enabled(json['reqd']),
      hidden = enabled(json['hidden']),
      readOnly = enabled(json['read_only']) || json['fieldtype'] == 'Read Only',
      allowOnSubmit = enabled(json['allow_on_submit']),
      defaultValue = json['default'],
      conditions = objectMap(json['conditions'] ?? <String, dynamic>{}),
      description = json['description']?.toString() ?? '';
  final String name, label, type, options, description;
  final bool required, hidden, readOnly, allowOnSubmit;
  final Object? defaultValue;
  final Map<String, dynamic> conditions;
  bool visible(Map<String, dynamic> data, Map<String, dynamic> parent) =>
      !hidden &&
      evaluateCondition(
            conditions['depends_on'] as Map<String, dynamic>?,
            data,
            parent: parent.isEmpty ? data : parent,
          ) !=
          false;
  bool mandatory(Map<String, dynamic> data, Map<String, dynamic> parent) =>
      required ||
      evaluateCondition(
            conditions['mandatory_depends_on'] as Map<String, dynamic>?,
            data,
            parent: parent.isEmpty ? data : parent,
          ) ==
          true;
  bool locked(Map<String, dynamic> data, Map<String, dynamic> parent) =>
      readOnly ||
      evaluateCondition(
            conditions['read_only_depends_on'] as Map<String, dynamic>?,
            data,
            parent: parent.isEmpty ? data : parent,
          ) ==
          true;
  bool get multiple => type == 'MultiSelectList' || type == 'MultiSelect';
  bool get table => type == 'Table' || type == 'Table MultiSelect';
  bool get layout => const {
    'Section Break',
    'Tab Break',
    'Column Break',
    'Heading',
    'HTML',
    'Button',
    'Image',
  }.contains(type);
  bool get numeric =>
      const {'Int', 'Float', 'Currency', 'Percent', 'Duration'}.contains(type);
  Object? parse(Object? value) {
    if (multiple) {
      if (value == null || value == '') return <String>[];
      if (value is! List || value.any((v) => v is! String)) {
        throw FormatException('$label must contain selected records.');
      }
      return List<String>.from(value);
    }
    if (value == null || value == '') return numeric ? null : value;
    if (type == 'Check') return enabled(value) ? 1 : 0;
    if (type == 'Barcode') return encodeBarcode(value.toString(), options);
    if (!numeric) return value;
    final number = num.tryParse(value.toString());
    if (number == null ||
        !number.isFinite ||
        type == 'Int' && number != number.roundToDouble()) {
      throw FormatException(
        '$label must be a valid ${type == 'Int' ? 'whole number' : 'number'}.',
      );
    }
    return type == 'Int' ? number.toInt() : number;
  }
}

class NativeSchema {
  NativeSchema.fromJson(Map<String, dynamic> json)
    : doctype = json['doctype'] as String,
      promptName = json['autoname']?.toString().toLowerCase() == 'prompt',
      operationRecoverySupported =
          json['operation_recovery_supported'] != false,
      operationRecoveryReason = json['operation_recovery_reason']?.toString(),
      fields = (json['fields'] as List)
          .map((f) => NativeField.fromJson(objectMap(f)))
          .toList(),
      children = {
        for (final entry in objectMap(
          json['children'] ?? <String, dynamic>{},
        ).entries)
          entry.key: NativeSchema.fromJson(objectMap(entry.value)),
      },
      permissions = objectMap(json['permissions'] ?? <String, dynamic>{}),
      partyDefaults = enabled(json['party_defaults']),
      itemDefaults = enabled(json['item_defaults']),
      preparable = enabled(json['preparable']),
      single = enabled(json['single']),
      submittable = enabled(json['submittable']),
      titleField = json['title_field']?.toString() ?? 'name';
  final String doctype, titleField;
  final bool operationRecoverySupported;
  final String? operationRecoveryReason;
  final List<NativeField> fields;
  final Map<String, NativeSchema> children;
  final Map<String, dynamic> permissions;
  final bool single,
      submittable,
      preparable,
      partyDefaults,
      itemDefaults,
      promptName;
  static final _documentName = NativeField.fromJson({
    'fieldname': '__newname',
    'fieldtype': 'Data',
    'label': 'Document name',
    'reqd': 1,
  });
  bool _needsName(Map<String, dynamic> data) =>
      promptName && (enabled(data['__islocal']) || data['name'] == null);

  Iterable<NativeField> visibleFields(
    Map<String, dynamic> data, {
    Map<String, dynamic> parent = const {},
  }) sync* {
    if (_needsName(data)) yield _documentName;
    bool tabHidden = false, sectionHidden = false;
    for (final f in fields) {
      final visible = f.visible(data, parent);
      if (f.type == 'Tab Break') {
        tabHidden = !visible;
        sectionHidden = false;
      } else if (f.type == 'Section Break') {
        sectionHidden = !visible;
      }
      if (visible && !tabHidden && !sectionHidden) yield f;
    }
  }

  Map<String, String> validate(
    Map<String, dynamic> data, {
    Map<String, dynamic> parent = const {},
  }) {
    final errors = <String, String>{};
    for (final field in visibleFields(
      data,
      parent: parent,
    ).where((f) => !f.locked(data, parent) && !f.layout)) {
      final value = data[field.name];
      if (field.mandatory(data, parent) &&
          (value == null ||
              value.toString().trim().isEmpty ||
              value is List && value.isEmpty)) {
        errors[field.name] = '${field.label} is required.';
      } else {
        try {
          field.parse(value);
        } on FormatException catch (e) {
          errors[field.name] = e.message;
        }
      }
      if (field.table && value is List) {
        final child = children[field.options];
        for (var i = 0; i < value.length && child != null; i++) {
          for (final entry
              in child.validate(objectMap(value[i]), parent: data).entries) {
            errors['${field.name}.$i.${entry.key}'] =
                'Row ${i + 1}: ${entry.value}';
          }
        }
      }
    }
    return errors;
  }

  Map<String, dynamic> payload(Map<String, dynamic> data) => {
    'doctype': doctype,
    if (_needsName(data) && data['__newname'] != null)
      '__newname': data['__newname'],
    if (data['__native_origin'] != null)
      '__native_origin': data['__native_origin'],
    if (data['name'] != null) 'name': data['name'],
    if (data['modified'] != null) 'modified': data['modified'],
    if (enabled(data['__islocal'])) '__islocal': 1,
    for (final field in fields.where(
      (f) =>
          !f.layout &&
          !f.readOnly &&
          !f.hidden &&
          (data['docstatus'] != 1 || f.allowOnSubmit) &&
          data.containsKey(f.name),
    ))
      field.name: field.table
          ? [
              for (final row in data[field.name] as List? ?? [])
                children[field.options]!.payload(objectMap(row)),
            ]
          : field.parse(data[field.name]),
  };
}

class NativeDocument {
  NativeDocument.fromJson(Map<String, dynamic> json)
    : data = objectMap(json['doc']),
      permissions = objectMap(json['permissions'] ?? <String, dynamic>{}),
      workflow = json['workflow']?.toString() ?? '',
      relatedActions = List<String>.from(
        json['related_actions'] as List? ?? [],
      ),
      transitions = (json['transitions'] as List? ?? [])
          .map(objectMap)
          .toList();
  final Map<String, dynamic> data, permissions;
  final String workflow;
  final List<String> relatedActions;
  final List<Map<String, dynamic>> transitions;
  bool get isNew => enabled(data['__islocal']) || data['name'] == null;
  bool can(String action) => enabled(permissions[action]);
  Map<String, dynamic> editCopy() => objectMap(jsonDecode(jsonEncode(data)));
}

class NativeType {
  NativeType.fromJson(Map<String, dynamic> json)
    : name = json['name'] as String,
      module = json['module']?.toString() ?? 'Other',
      single = enabled(json['issingle']),
      tree = enabled(json['is_tree']),
      canImport = enabled(json['can_import']),
      canGroup = enabled(json['can_group']),
      canCreate = enabled(json['create']);
  final String name, module;
  final bool single, tree, canCreate, canImport, canGroup;
}

class NativeCatalog {
  NativeCatalog.fromJson(Map<String, dynamic> json)
    : site = json['site']?.toString() ?? '',
      types = (json['types'] as List)
          .map((t) => NativeType.fromJson(objectMap(t)))
          .toList(),
      reports = (json['reports'] as List).map(objectMap).toList() {
    if (json['version'] != 1) {
      throw const FormatException('Unsupported native server version.');
    }
  }
  final List<NativeType> types;
  final String site;
  final List<Map<String, dynamic>> reports;
}

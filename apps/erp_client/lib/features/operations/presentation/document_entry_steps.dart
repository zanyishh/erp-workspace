import 'package:flutter/material.dart';

import '../../../core/models/native_models.dart';
import '../../../core/ui/widgets.dart';

class DocumentEntryStep {
  const DocumentEntryStep(this.key, this.label, this.fields);

  final String key, label;
  final List<NativeField> fields;

  bool containsError(String path) {
    final name = path.split('.').first;
    return fields.any((field) => field.name == name);
  }

  static List<DocumentEntryStep> forDraft(
    NativeSchema schema,
    Map<String, dynamic> data,
  ) {
    // Small forms already fit the ordinary editor. Use the schema size so
    // entering a value that hides a field cannot change the form's mode.
    if (schema.fields.where((f) => !f.layout && !f.hidden).length < 8) {
      return const [];
    }
    final visible = schema.visibleFields(data).toList();
    final tabs = _group(visible, const {'Tab Break'});
    if (tabs.length > 1) {
      final largeTabs = {
        for (final tab in _group(schema.fields, const {'Tab Break'}))
          if (tab.fields.where((f) => !f.hidden && !f.layout).length > 16)
            tab.key,
      };
      return [
        for (final tab in tabs)
          ..._sectionsForTab(tab, largeTabs.contains(tab.key)),
      ];
    }
    final sections = _group(visible, const {'Section Break', 'Heading'});
    return sections.length > 1 ? sections : const [];
  }

  static List<DocumentEntryStep> _sectionsForTab(
    DocumentEntryStep tab,
    bool large,
  ) {
    if (!large) return [tab];
    final sections = _group(tab.fields, const {'Section Break', 'Heading'});
    if (sections.length < 2) return [tab];
    return [
      for (final section in sections)
        DocumentEntryStep(
          '${tab.key}/${section.key}',
          section.key.isEmpty ? tab.label : section.label,
          section.fields,
        ),
    ];
  }

  static List<DocumentEntryStep> _group(
    List<NativeField> visible,
    Set<String> boundaries,
  ) {
    final steps = <DocumentEntryStep>[];
    var key = '', label = 'Details';
    var fields = <NativeField>[];
    void finish() {
      if (fields.any((field) => !field.layout)) {
        steps.add(DocumentEntryStep(key, label, fields));
      }
      fields = [];
    }

    for (final field in visible) {
      if (boundaries.contains(field.type) &&
          field.label.isNotEmpty &&
          field.label != field.name) {
        finish();
        key = field.name;
        label = field.label;
      } else {
        fields.add(field);
      }
    }
    finish();
    return steps;
  }
}

class DocumentEntryNavigation extends StatelessWidget {
  const DocumentEntryNavigation({
    super.key,
    required this.index,
    required this.count,
    required this.onBack,
    required this.onProceed,
  });

  final int index, count;
  final VoidCallback? onBack, onProceed;

  @override
  Widget build(BuildContext context) => Panel(
    frosted: true,
    radius: 0,
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1080),
        child: Row(
          children: [
            Expanded(
              child: Semantics(
                liveRegion: true,
                child: Text('Step ${index + 1} of $count'),
              ),
            ),
            if (index > 0)
              TextButton(onPressed: onBack, child: const Text('Back')),
            const SizedBox(width: 6),
            FilledButton(
              onPressed: onProceed,
              child: Text(index + 1 < count ? 'Next' : 'Save'),
            ),
          ],
        ),
      ),
    ),
  );
}

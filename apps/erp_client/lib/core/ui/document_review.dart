import 'package:flutter/material.dart';

import 'formatted_text.dart';
import '../models/native_models.dart';

/// Reviews use only the server's field projection, never a second financial fetch.
class DocumentReview extends StatelessWidget {
  const DocumentReview({
    super.key,
    required this.schema,
    required this.document,
    required this.action,
    this.onPreviewDraft,
  });
  final NativeSchema schema;
  final Map<String, dynamic> document;
  final String action;
  final VoidCallback? onPreviewDraft;

  List<Widget> _details(
    BuildContext context,
    NativeSchema schema,
    Map<String, dynamic> values, {
    required bool stacked,
    Map<String, dynamic> parent = const {},
  }) {
    final theme = Theme.of(context);
    final details = <Widget>[];
    for (final field in schema.visibleFields(values, parent: parent)) {
      final value = values[field.name];
      if (field.layout ||
          value == null ||
          value == '' ||
          field.type == 'Password') {
        continue;
      }
      if (field.table) {
        final child = schema.children[field.options];
        if (child == null || value is! List || value.isEmpty) continue;
        details.add(
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 4),
            child: Text(
              '${field.label} (${value.length})',
              style: theme.textTheme.titleSmall,
            ),
          ),
        );
        for (final (index, row) in value.indexed) {
          details.add(
            Container(
              decoration: BoxDecoration(
                border: BorderDirectional(
                  start: BorderSide(
                    color: theme.colorScheme.outlineVariant,
                    width: 2,
                  ),
                ),
              ),
              margin: const EdgeInsets.only(top: 6, bottom: 6),
              padding: const EdgeInsetsDirectional.only(start: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Row ${index + 1}', style: theme.textTheme.labelMedium),
                  ..._details(
                    context,
                    child,
                    objectMap(row),
                    parent: values,
                    stacked: stacked,
                  ),
                ],
              ),
            ),
          );
        }
        continue;
      }
      final label = Text(
        field.label,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      );
      final Widget display;
      if (field.type == 'Text Editor') {
        display = FormattedTextPreview(value.toString());
      } else {
        final text = switch (field.type) {
          'Check' => enabled(value) ? 'Yes' : 'No',
          'Signature' => 'Signature provided',
          'Attach Image' => 'Image attached',
          'Geolocation' => 'Location recorded',
          _ when field.multiple && value is List => value.join(', '),
          _ => value.toString(),
        };
        display = Text(
          text,
          textAlign: field.numeric && !stacked
              ? TextAlign.end
              : TextAlign.start,
          style: field.numeric
              ? const TextStyle(fontFeatures: [FontFeature.tabularFigures()])
              : null,
        );
      }
      details.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: MergeSemantics(
            child: stacked
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [label, const SizedBox(height: 2), display],
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Expanded(flex: 2, child: label),
                      const SizedBox(width: 12),
                      Expanded(flex: 3, child: display),
                    ],
                  ),
          ),
        ),
      );
    }
    return details;
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 560,
    child: LayoutBuilder(
      builder: (context, constraints) {
        final stacked =
            constraints.maxWidth < 290 ||
            MediaQuery.textScalerOf(context).scale(16) > 22;
        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (document['name'] case final String name when name.isNotEmpty)
                Text(name, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(switch (action) {
                'Submit' => 'Submission applies this document and its configured postings. Later changes may require cancellation or amendment.',
                'Cancel' => 'Cancellation reverses this document’s postings. Linked documents can prevent cancellation.',
                _ =>
                  'Apply $action to this record using its current saved values.',
              }),
              if (onPreviewDraft != null)
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton.icon(
                    icon: const Icon(Icons.picture_as_pdf_outlined),
                    label: const Text('Preview draft PDF'),
                    onPressed: onPreviewDraft,
                  ),
                ),
              const Divider(height: 24),
              ..._details(context, schema, document, stacked: stacked),
            ],
          ),
        );
      },
    ),
  );
}

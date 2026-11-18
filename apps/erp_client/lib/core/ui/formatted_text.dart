import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html;

// Flutter draws text spans only. No browser, image provider, URL launcher or remote fonts.
class _FormattedContent {
  _FormattedContent(String source) {
    for (final node in html.parseFragment(source, generateSpans: true).nodes) {
      _visit(node, const TextStyle());
    }
    while (preview.isNotEmpty && preview.last.text == '\n') {
      preview.removeLast();
    }
  }
  final preview = <TextSpan>[];
  final runs = <({String text, int start, int end, TextStyle style})>[];
  int _listDepth = 0;

  void _break() {
    if (preview.isNotEmpty && preview.last.text != '\n') {
      preview.add(const TextSpan(text: '\n'));
    }
  }

  void _visit(dom.Node node, TextStyle style) {
    if (node is dom.Text) {
      if (node.data.isEmpty) return;
      final span = node.sourceSpan;
      if (span != null && node.data.trim().isNotEmpty) {
        runs.add((
          text: node.data,
          start: span.start.offset,
          end: span.end.offset,
          style: style,
        ));
      }
      preview.add(TextSpan(text: node.data, style: style));
      return;
    }
    if (node is! dom.Element ||
        node.namespaceUri != 'http://www.w3.org/1999/xhtml') {
      return;
    }
    final tag = node.localName;
    if (const {
          'head',
          'style',
          'script',
          'link',
          'iframe',
          'object',
          'embed',
          'canvas',
          'audio',
          'video',
          'source',
          'noscript',
          'template',
          'img',
          'input',
          'button',
          'textarea',
        }.contains(tag) ||
        node.attributes.containsKey('hidden')) {
      return;
    }
    if (tag == 'br') {
      _break();
      return;
    }
    final block = const {
      'p',
      'div',
      'section',
      'blockquote',
      'h1',
      'h2',
      'h3',
      'h4',
      'ol',
      'ul',
      'li',
      'tr',
      'pre',
    }.contains(tag);
    if (block) _break();
    final nested = switch (tag) {
      'strong' || 'b' => style.copyWith(fontWeight: FontWeight.bold),
      'em' || 'i' => style.copyWith(fontStyle: FontStyle.italic),
      'u' || 'a' => style.copyWith(decoration: TextDecoration.underline),
      's' || 'del' => style.copyWith(decoration: TextDecoration.lineThrough),
      'h1' ||
      'h2' ||
      'h3' ||
      'h4' => style.copyWith(fontSize: 19, fontWeight: FontWeight.bold),
      _ => style,
    };
    if (tag == 'ol' || tag == 'ul') _listDepth++;
    if (tag == 'li') {
      final siblings = node.parent?.children
          .where((e) => e.localName == 'li')
          .toList();
      final marker = node.parent?.localName == 'ol' && siblings != null
          ? '${siblings.indexOf(node) + 1}.'
          : '•';
      preview.add(
        TextSpan(
          text: '${'  ' * (_listDepth > 0 ? _listDepth - 1 : 0)}$marker ',
        ),
      );
    }
    for (final child in node.nodes) {
      _visit(child, nested);
    }
    if (tag == 'ol' || tag == 'ul') _listDepth--;
    if (block) _break();
  }
}

/// Read-only rendering for document review. The same parser used in the editor
/// decodes entities, preserves text formatting and skips embedded content.
class FormattedTextPreview extends StatelessWidget {
  const FormattedTextPreview(this.source, {super.key});
  final String source;

  @override
  Widget build(BuildContext context) {
    final spans = _FormattedContent(source).preview;
    return spans.isEmpty
        ? const Text('Embedded content')
        : Text.rich(TextSpan(children: spans));
  }
}

class FormattedTextField extends StatefulWidget {
  const FormattedTextField({
    super.key,
    required this.label,
    required this.value,
    required this.editable,
    required this.onChanged,
    this.error,
  });
  final String label, value;
  final bool editable;
  final String? error;
  final ValueChanged<String> onChanged;
  @override
  State<FormattedTextField> createState() => _FormattedTextFieldState();
}

class _FormattedTextFieldState extends State<FormattedTextField> {
  late _FormattedContent content = _FormattedContent(widget.value);
  @override
  void didUpdateWidget(FormattedTextField old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value) content = _FormattedContent(widget.value);
  }

  Future<void> _edit() async {
    final original = widget.value;
    final edited = await showDialog<String>(
      context: context,
      builder: (_) => _EditFormattedText(
        source: original,
        label: widget.label,
        content: content,
      ),
    );
    if (!mounted || !widget.editable || edited == null || edited == original) {
      return;
    }
    if (widget.value != original) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'This field changed. Open it again to edit the latest text.',
          ),
        ),
      );
      return;
    }
    widget.onChanged(edited);
  }

  @override
  Widget build(BuildContext context) => InputDecorator(
    decoration: InputDecoration(
      labelText: widget.label,
      floatingLabelBehavior: FloatingLabelBehavior.always,
      errorText: widget.error,
      suffixIcon: widget.editable
          ? IconButton(
              tooltip: 'Edit ${widget.label}',
              onPressed: _edit,
              icon: const Icon(Icons.edit_note_outlined),
            )
          : null,
    ),
    child: content.preview.isEmpty
        ? Text(
            widget.value.isEmpty ? '—' : 'Embedded content',
            style: Theme.of(context).textTheme.bodySmall,
          )
        : Text.rich(TextSpan(children: content.preview)),
  );
}

class _EditFormattedText extends StatefulWidget {
  const _EditFormattedText({
    required this.source,
    required this.label,
    required this.content,
  });
  final String source, label;
  final _FormattedContent content;
  @override
  State<_EditFormattedText> createState() => _EditFormattedTextState();
}

class _EditFormattedTextState extends State<_EditFormattedText> {
  late final List<TextEditingController> controllers = [
    for (final r in widget.content.runs) TextEditingController(text: r.text),
  ];
  final added = TextEditingController();
  String paragraph = 'Paragraph';
  @override
  void dispose() {
    for (final c in controllers) {
      c.dispose();
    }
    added.dispose();
    super.dispose();
  }

  String _escape(String value) =>
      const HtmlEscape(HtmlEscapeMode.element)
          .convert(value)
          .replaceAll('\n', '<br>');

  void _apply() {
    var source = widget.source;
    // Replace only the source bytes of explicitly changed text nodes. Rich markup
    // outside those ranges (including unsupported tags and attributes) stays intact.
    final changes = [
      for (final (i, r) in widget.content.runs.indexed)
        if (controllers[i].text != r.text)
          (start: r.start, end: r.end, value: _escape(controllers[i].text)),
    ]..sort((a, b) => b.start.compareTo(a.start));
    var limit = source.length;
    for (final c in changes) {
      if (c.start < 0 || c.end > limit || c.end < c.start) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('This text cannot be edited safely in place.'),
          ),
        );
        return;
      }
      source = source.replaceRange(c.start, c.end, c.value);
      limit = c.start;
    }
    if (added.text.isNotEmpty) {
      final text = _escape(added.text);
      source += switch (paragraph) {
        'Heading' => '<h2>$text</h2>',
        'Bold' => '<p><strong>$text</strong></p>',
        'Italic' => '<p><em>$text</em></p>',
        'List item' => '<ul><li>$text</li></ul>',
        _ => '<p>$text</p>',
      };
    }
    Navigator.pop(context, source);
  }

  @override
  Widget build(BuildContext context) => Dialog.fullscreen(
    child: Scaffold(
      appBar: AppBar(
        title: Text(widget.label),
        leading: IconButton(
          tooltip: 'Cancel edits',
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [TextButton(onPressed: _apply, child: const Text('Apply'))],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          for (final (i, r) in widget.content.runs.indexed)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: TextField(
                controller: controllers[i],
                minLines: 1,
                maxLines: null,
                style: r.style,
                decoration: InputDecoration(labelText: 'Text ${i + 1}'),
              ),
            ),
          DropdownButtonFormField<String>(
            initialValue: paragraph,
            decoration: const InputDecoration(labelText: 'New paragraph style'),
            items: [
              for (final kind in [
                'Paragraph',
                'Heading',
                'Bold',
                'Italic',
                'List item',
              ])
                DropdownMenuItem(value: kind, child: Text(kind)),
            ],
            onChanged: (v) => setState(() => paragraph = v ?? 'Paragraph'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: added,
            minLines: 2,
            maxLines: null,
            decoration: const InputDecoration(labelText: 'Add text'),
          ),
        ],
      ),
    ),
  );
}

import 'package:flutter/material.dart';

import '../models/invoice_print_data.dart';
import '../models/invoice_paper.dart';
import '../models/invoice_templates.dart';
import 'invoice_gallery.dart';
import 'invoice_preview_view_model.dart';

class InvoicePreviewView extends StatefulWidget {
  const InvoicePreviewView({
    super.key,
    required this.model,
    this.invoice,
    this.initialTemplate,
    this.onCreate,
    this.transitionTag,
    required this.preview,
    required this.platform,
    required this.protect,
  });
  final InvoicePreviewViewModel model;
  final String? invoice;
  final InvoiceTemplate? initialTemplate;
  final ValueChanged<InvoiceTemplate>? onCreate;
  final Object? transitionTag;
  final Widget Function(InvoicePdfFile) preview;
  final Future<void> Function(
    InvoicePdfFile,
    Future<InvoicePdfFile> Function(),
    bool,
  )
  platform;
  final Widget Function(Widget, Future<void> Function()) protect;
  @override
  State<InvoicePreviewView> createState() => _InvoicePreviewViewState();
}

class _InvoicePreviewViewState extends State<InvoicePreviewView> {
  bool get sample => widget.model.source.kind == InvoiceSourceKind.sample;
  bool get working => widget.model.working;
  bool get choseStyle => widget.model.choseStyle;
  InvoiceTemplate get selected => widget.model.selected;
  Widget paper(Widget child) =>
      sample &&
          widget.initialTemplate != null &&
          (!choseStyle || selected.id == widget.initialTemplate!.id)
      ? InvoicePaperContinuity(
          tag: widget.transitionTag,
          template: widget.initialTemplate!,
          child: child,
        )
      : child;
  Future<void> _refresh() async {
    await widget.model.reload();
  }

  Future<void> _select() async {
    final model = widget.model, intent = model.prepareSelection();
    if (intent == null) return;
    final choice = await chooseInvoiceTemplate(context, model.selected.id);
    if (choice != null && mounted && identical(model, widget.model)) {
      model.selectTemplate(intent, choice);
    }
  }

  Future<void> _choosePaper() async {
    final model = widget.model, intent = model.prepareSelection();
    if (intent == null) return;
    final picked = await showDialog<InvoicePaper>(
      context: context,
      builder: (dialog) => SimpleDialog(
        title: const Text('Paper size'),
        children: [
          for (final option in InvoicePaper.values)
            ListTile(
              title: Text(option.label),
              selected: model.paper == option,
              trailing: model.paper == option ? const Icon(Icons.check) : null,
              onTap: () => Navigator.pop(dialog, option),
            ),
        ],
      ),
    );
    if (picked != null && mounted && identical(widget.model, model)) {
      model.selectPaper(intent, picked);
    }
  }

  Future<void> _saveStyle({bool inherit = false}) async {
    final model = widget.model;
    final saved = await model.saveStyle(inherit: inherit);
    if (!mounted || !identical(model, widget.model)) return;
    if (saved) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            inherit
                ? 'This invoice now uses the company default.'
                : '${model.selected.name} saved for ${widget.invoice}.',
          ),
        ),
      );
    } else if (model.problem != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(model.problem!)));
    }
  }

  Future<void> _export({required bool print}) async {
    final model = widget.model, captured = model.scope;
    try {
      await model.exportTo(
        (file, reauthorize) => widget.platform(file, reauthorize, print),
      );
    } catch (error) {
      if (mounted &&
          identical(model, widget.model) &&
          model.isCurrent(captured) &&
          model.dataError == null) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  Widget _compactControls() {
    final model = widget.model, scope = model.scope;
    final actions = <String, VoidCallback>{
      if (model.canSaveStyle) 'Save template': () => _saveStyle(),
      if (model.canInherit)
        'Use company default': () => _saveStyle(inherit: true),
      'Paper size · ${model.paper.label}': _choosePaper,
      'Print': () => _export(print: true),
    };
    return Row(
      children: [
        Expanded(
          child: Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: working ? null : _select,
              icon: const Icon(Icons.style_outlined, size: 18),
              label: Text(
                selected.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ),
        if (sample && widget.onCreate != null)
          IconButton(
            tooltip: 'Use for new invoice',
            onPressed: working ? null : () => widget.onCreate!(selected),
            icon: const Icon(Icons.note_add_outlined),
          ),
        IconButton(
          tooltip: 'Export PDF',
          icon: const Icon(Icons.ios_share_outlined),
          onPressed: working ? null : () => _export(print: false),
        ),
        PopupMenuButton<String>(
          enabled: !working,
          tooltip: 'More invoice actions',
          itemBuilder: (_) => [
            for (final label in actions.keys)
              PopupMenuItem(value: label, child: Text(label)),
          ],
          onSelected: (label) {
            if (mounted &&
                identical(model, widget.model) &&
                model.isCurrent(scope) &&
                !working) {
              actions[label]?.call();
            }
          },
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.model,
    builder: (context, _) => widget.protect(
      Scaffold(
        appBar: AppBar(
          title: Text(
            sample ? 'Template preview' : widget.invoice ?? 'Original invoice',
          ),
        ),
        body: SafeArea(
          child: FutureBuilder<InvoicePrintData>(
            key: ValueKey((widget.model, widget.model.scope)),
            future: widget.model.data,
            builder: (context, state) {
              if (state.connectionState != ConnectionState.done) {
                return Column(
                  children: [
                    const SizedBox(height: 64),
                    Expanded(
                      child: paper(
                        Center(
                          child: widget.initialTemplate == null
                              ? const CircularProgressIndicator()
                              : Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.all(16),
                                      child: Image.asset(
                                        widget.initialTemplate!.thumbnailAsset,
                                        fit: BoxFit.contain,
                                      ),
                                    ),
                                    const CircularProgressIndicator(
                                      semanticsLabel:
                                          'Preparing template preview',
                                    ),
                                  ],
                                ),
                        ),
                      ),
                    ),
                  ],
                );
              }
              if (state.hasError || widget.model.dataError != null) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          (widget.model.dataError ?? state.error).toString(),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        OutlinedButton(
                          onPressed: () => _refresh().catchError((_) {}),
                          child: const Text('Try again'),
                        ),
                      ],
                    ),
                  ),
                );
              }
              final canSave = widget.model.canSaveStyle;
              final size = MediaQuery.sizeOf(context);
              final short = size.height < 530;
              final compact =
                  short ||
                  size.width < 600 ||
                  MediaQuery.textScalerOf(context).scale(14) > 22;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (widget.model.source.draftRevision == null)
                    Padding(
                      padding: EdgeInsets.fromLTRB(
                        16,
                        short ? 0 : 8,
                        16,
                        short ? 3 : 10,
                      ),
                      child: compact
                          ? _compactControls()
                          : Wrap(
                              spacing: 8,
                              runSpacing: 4,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                OutlinedButton.icon(
                                  onPressed: working ? null : _select,
                                  icon: const Icon(
                                    Icons.style_outlined,
                                    size: 19,
                                  ),
                                  label: Text(selected.name),
                                ),
                                OutlinedButton.icon(
                                  onPressed: working ? null : _choosePaper,
                                  icon: const Icon(
                                    Icons.description_outlined,
                                    size: 18,
                                  ),
                                  label: Text(widget.model.paper.label),
                                ),
                                if (canSave)
                                  FilledButton(
                                    onPressed: working
                                        ? null
                                        : () => _saveStyle(),
                                    child: const Text('Save template'),
                                  ),
                                if (widget.model.canInherit)
                                  TextButton(
                                    onPressed: working
                                        ? null
                                        : () => _saveStyle(inherit: true),
                                    child: const Text('Use company default'),
                                  ),
                                if (sample && widget.onCreate != null)
                                  FilledButton(
                                    onPressed: working
                                        ? null
                                        : () => widget.onCreate!(selected),
                                    child: const Text('Use for new invoice'),
                                  ),
                                TextButton.icon(
                                  onPressed: working
                                      ? null
                                      : () => _export(print: false),
                                  icon: const Icon(
                                    Icons.ios_share_outlined,
                                    size: 18,
                                  ),
                                  label: const Text('Export PDF'),
                                ),
                                TextButton.icon(
                                  onPressed: working
                                      ? null
                                      : () => _export(print: true),
                                  icon: const Icon(
                                    Icons.print_outlined,
                                    size: 18,
                                  ),
                                  label: const Text('Print'),
                                ),
                              ],
                            ),
                    ),
                  if (working) const LinearProgressIndicator(minHeight: 2),
                  Expanded(
                    child: paper(
                      FutureBuilder<InvoicePdfFile>(
                        key: ValueKey((widget.model, widget.model.pdfScope)),
                        future: widget.model.pdf,
                        builder: (context, result) {
                          if (result.connectionState != ConnectionState.done) {
                            return const Center(
                              child: CircularProgressIndicator(),
                            );
                          }
                          if (result.hasError) {
                            return Center(
                              child: Text(
                                'Could not prepare this PDF. ${result.error}',
                                textAlign: TextAlign.center,
                              ),
                            );
                          }
                          final file = result.requireData;
                          if (!widget.model.canUse(file)) {
                            return const Center(
                              child: CircularProgressIndicator(),
                            );
                          }
                          return widget.preview(file);
                        },
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
      _refresh,
    ),
  );
}

import 'package:flutter/material.dart';

import 'original_record_preview_view_model.dart';

class OriginalRecordPreviewView extends StatefulWidget {
  const OriginalRecordPreviewView({
    super.key,
    required this.model,
    required this.preview,
    required this.platform,
    required this.protect,
  });
  final OriginalRecordPreviewViewModel model;
  final Widget Function(OriginalPdfFile) preview;
  final Future<void> Function(
    OriginalPdfFile,
    Future<OriginalPdfFile> Function(),
    bool,
  )
  platform;
  final Widget Function(Widget, Future<void> Function()) protect;
  @override
  State<OriginalRecordPreviewView> createState() =>
      _OriginalRecordPreviewViewState();
}

class _OriginalRecordPreviewViewState extends State<OriginalRecordPreviewView> {
  bool get working => widget.model.working;
  Future<void> _refresh() async {
    await widget.model.reload();
  }

  Future<void> _export({required bool print}) async {
    final model = widget.model;
    try {
      await model.exportTo(
        (file, reauthorize) => widget.platform(file, reauthorize, print),
      );
    } catch (error) {
      if (mounted && identical(model, widget.model) && !model.errorInPreview) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.model,
    builder: (context, _) => widget.protect(
      Scaffold(
        appBar: AppBar(title: const Text('Original record preview')),
        body: FutureBuilder<OriginalPdfFile>(
          key: ValueKey(widget.model.scope),
          future: widget.model.result,
          builder: (context, state) {
            if (state.hasError || widget.model.previewError != null) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        (widget.model.previewError ?? state.error).toString(),
                      ),
                      TextButton(
                        onPressed: () => _refresh().catchError((_) {}),
                        child: const Text('Try again'),
                      ),
                    ],
                  ),
                ),
              );
            }
            if (state.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            final file = state.requireData;
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Wrap(
                    spacing: 12,
                    children: [
                      TextButton.icon(
                        onPressed: working ? null : () => _export(print: false),
                        icon: const Icon(Icons.ios_share_outlined),
                        label: const Text('Export PDF'),
                      ),
                      TextButton.icon(
                        onPressed: working ? null : () => _export(print: true),
                        icon: const Icon(Icons.print_outlined),
                        label: const Text('Print'),
                      ),
                    ],
                  ),
                ),
                if (working) const LinearProgressIndicator(minHeight: 2),
                Expanded(child: widget.preview(file)),
              ],
            );
          },
        ),
      ),
      _refresh,
    ),
  );
}

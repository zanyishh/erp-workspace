import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../../erp_api.dart' show ErpApi;
import '../../features/imported_history/data/erp_history_repository.dart';
import '../../features/imported_history/data/imported_record_pdf_service.dart';
import '../../features/imported_history/presentation/original_record_preview_view.dart';
import '../../features/imported_history/presentation/original_record_preview_view_model.dart';
import '../gates/access_gate.dart';

class ImportedRecordPreviewScreen extends StatefulWidget {
  const ImportedRecordPreviewScreen({
    super.key,
    required this.api,
    required this.company,
    required this.name,
  });
  final ErpApi api;
  final String company, name;
  @override
  State<ImportedRecordPreviewScreen> createState() =>
      _ImportedRecordPreviewScreenState();
}

class _ImportedRecordPreviewScreenState
    extends State<ImportedRecordPreviewScreen> {
  late ErpImportedHistoryRepository _repository;
  late OriginalRecordPreviewViewModel _model;
  late Object _owned;
  Object? _access;
  Object get _ownership => (
    widget.api,
    widget.api.baseUri,
    widget.api.account,
    widget.company,
    widget.name,
  );
  void _create() {
    _owned = _ownership;
    _repository = ErpImportedHistoryRepository(
      api: widget.api,
      company: widget.company,
    );
    _access = _repository.scope;
    _model = OriginalRecordPreviewViewModel(
      _repository,
      name: widget.name,
      render: renderOriginalRecordPdf,
    );
  }

  @override
  void initState() {
    super.initState();
    _create();
    widget.api.addAccessListener(_accessChanged);
  }

  void _accessChanged() {
    if (!mounted) return;
    if (_owned != _ownership) {
      _model.dispose();
      _create();
      setState(() {});
    } else if (_access != _repository.scope) {
      _access = _repository.scope;
      setState(() {});
    }
  }

  @override
  void didUpdateWidget(covariant ImportedRecordPreviewScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.api != widget.api) {
      oldWidget.api.removeAccessListener(_accessChanged);
      widget.api.addAccessListener(_accessChanged);
    }
    if (_owned != _ownership) {
      _model.dispose();
      _create();
    }
  }

  @override
  void dispose() {
    widget.api.removeAccessListener(_accessChanged);
    _model.dispose();
    super.dispose();
  }

  Future<void> _platform(
    OriginalPdfFile file,
    Future<OriginalPdfFile> Function() reauthorize,
    bool print,
  ) async {
    if (print) {
      await Printing.layoutPdf(
        name: file.filename,
        format: PdfPageFormat.a4,
        dynamicLayout: false,
        onLayout: (_) async => (await reauthorize()).bytes,
      );
    } else if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
      final location = await getSaveLocation(suggestedName: file.filename);
      if (location == null) return;
      final current = await reauthorize();
      await XFile.fromData(
        current.bytes,
        name: current.filename,
        mimeType: 'application/pdf',
      ).saveTo(location.path);
    } else {
      if (!mounted) return;
      final box = context.findRenderObject() as RenderBox?;
      await SharePlus.instance.share(
        ShareParams(
          files: [
            XFile.fromData(
              file.bytes,
              name: file.filename,
              mimeType: 'application/pdf',
            ),
          ],
          fileNameOverrides: [file.filename],
          sharePositionOrigin: box == null
              ? null
              : box.localToGlobal(Offset.zero) & box.size,
        ),
      );
    }
  }

  Widget _preview(OriginalPdfFile file) => PdfPreview(
    key: ObjectKey(file.bytes),
    build: (_) => file.bytes,
    initialPageFormat: PdfPageFormat.a4,
    dynamicLayout: false,
    canChangeOrientation: false,
    canChangePageFormat: false,
    canDebug: false,
    allowSharing: false,
    allowPrinting: false,
    useActions: false,
    maxPageWidth: 730,
    scrollViewDecoration: const BoxDecoration(color: Color(0xffdcdcd7)),
    onError: (_, _) => const Center(
      child: Text('Could not display this page. You can still export the PDF.'),
    ),
  );
  @override
  Widget build(BuildContext context) => OriginalRecordPreviewView(
    model: _model,
    preview: _preview,
    platform: _platform,
    protect: (child, reload) => AccessGate(
      key: ValueKey(_owned),
      api: widget.api,
      revalidate: reload,
      child: child,
    ),
  );
}

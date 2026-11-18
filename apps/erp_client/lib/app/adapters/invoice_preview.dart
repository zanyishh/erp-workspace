import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/models/erp_exception.dart';
import '../../core/ui/design.dart';
import '../../erp_api.dart' show ErpApi;
import '../../features/invoices/data/erp_invoice_repository.dart';
import '../../features/invoices/data/invoice_pdf_service.dart';
import '../../features/invoices/models/invoice_print_data.dart';
import '../../features/invoices/models/invoice_templates.dart';
import '../../features/invoices/presentation/invoice_preview_view.dart';
import '../../features/invoices/presentation/invoice_preview_view_model.dart';
import '../gates/access_gate.dart';

class InvoicePreviewScreen extends StatefulWidget {
  const InvoicePreviewScreen({
    super.key,
    required this.api,
    required this.company,
    this.invoice,
    this.draftRevision,
    this.initialTemplate,
    this.onCreate,
    this.importedRecord,
    this.transitionTag,
  });
  final ErpApi api;
  final String company;
  final String? invoice, importedRecord, draftRevision;
  final Object? transitionTag;
  final InvoiceTemplate? initialTemplate;
  final ValueChanged<InvoiceTemplate>? onCreate;
  @override
  State<InvoicePreviewScreen> createState() => _InvoicePreviewScreenState();
}

class _InvoicePreviewScreenState extends State<InvoicePreviewScreen> {
  late ErpInvoiceRepository _repository;
  late InvoicePreviewViewModel _model;
  late Object _owned;
  Object? _access;
  static const _changed = ErpException(
    'Access changed. Open the current invoice preview again.',
  );
  Object get _ownership => (
    widget.api,
    widget.api.baseUri,
    widget.api.account,
    widget.company,
    widget.invoice,
    widget.draftRevision,
    widget.importedRecord,
    widget.initialTemplate,
  );
  void _create() {
    _owned = _ownership;
    _repository = ErpInvoiceRepository(
      api: widget.api,
      company: widget.company,
    );
    _access = _repository.scope;
    final source = widget.importedRecord != null
        ? InvoicePreviewSource.original(widget.importedRecord!)
        : widget.invoice != null
        ? InvoicePreviewSource.native(
            widget.invoice!,
            draftRevision: widget.draftRevision,
          )
        : const InvoicePreviewSource.sample();
    _model = InvoicePreviewViewModel(
      _repository,
      source: source,
      initialTemplate: widget.initialTemplate,
      render: (style, value, paper) =>
          buildInvoicePdf(style, value.data, paper: paper),
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
  void didUpdateWidget(covariant InvoicePreviewScreen oldWidget) {
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
    InvoicePdfFile file,
    Future<InvoicePdfFile> Function() reauthorize,
    bool print,
  ) async {
    final model = _model;
    void require(InvoicePdfFile value) {
      if (!mounted || !identical(model, _model) || !model.canUse(value)) {
        throw _changed;
      }
    }

    require(file);
    if (print) {
      await Printing.layoutPdf(
        name: file.filename,
        format: file.paper.pageFormat,
        dynamicLayout: false,
        onLayout: (_) async {
          final fresh = await reauthorize();
          require(fresh);
          return fresh.bytes;
        },
      );
    } else if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
      final location = await getSaveLocation(suggestedName: file.filename);
      if (location == null) return;
      final fresh = await reauthorize();
      require(fresh);
      await XFile.fromData(
        fresh.bytes,
        name: fresh.filename,
        mimeType: 'application/pdf',
      ).saveTo(location.path);
    } else {
      final fresh = await reauthorize();
      if (!mounted) throw _changed;
      require(fresh);
      final box = context.findRenderObject() as RenderBox?;
      await SharePlus.instance.share(
        ShareParams(
          files: [
            XFile.fromData(
              fresh.bytes,
              name: fresh.filename,
              mimeType: 'application/pdf',
            ),
          ],
          fileNameOverrides: [fresh.filename],
          sharePositionOrigin: box == null
              ? null
              : box.localToGlobal(Offset.zero) & box.size,
        ),
      );
    }
  }

  Widget _preview(InvoicePdfFile file) {
    final model = _model;
    return PdfPreview(
      key: ObjectKey(file.bytes),
      build: (_) {
        if (!mounted || !identical(model, _model) || !model.canUse(file)) {
          throw _changed;
        }
        return file.bytes;
      },
      initialPageFormat: file.paper.pageFormat,
      dynamicLayout: false,
      canChangeOrientation: false,
      canChangePageFormat: false,
      canDebug: false,
      allowSharing: false,
      allowPrinting: false,
      useActions: false,
      maxPageWidth: file.paper.isReceipt ? file.paper.widthMm * 4 : 730,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      scrollViewDecoration: const BoxDecoration(color: Color(0xffdcdcd7)),
      pdfPreviewPageDecoration: const BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Color(0x22000000),
            blurRadius: 10,
            offset: Offset(0, 2),
          ),
        ],
      ),
      onError: (_, error) => Center(
        child: Text(
          'Could not display this page. You can still export the PDF.',
          style: TextStyle(color: WorkspaceTheme.ink),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => InvoicePreviewView(
    model: _model,
    invoice: widget.invoice,
    initialTemplate: widget.initialTemplate,
    onCreate: widget.onCreate,
    transitionTag: widget.transitionTag,
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

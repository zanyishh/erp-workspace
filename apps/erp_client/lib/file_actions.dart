import 'dart:io';
import 'dart:typed_data';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'erp_api.dart';
import 'ui/access_gate.dart';

Future<void> saveOrShareFile(
  BuildContext context,
  String name,
  Uint8List bytes, {
  String? mime,
}) async {
  final safe = name.replaceAll(RegExp(r'[/\\\x00-\x1f]'), '_');
  if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
    final location = await getSaveLocation(suggestedName: safe);
    if (location != null) {
      await XFile.fromData(
        bytes,
        name: safe,
        mimeType: mime,
      ).saveTo(location.path);
    }
  } else {
    final box = context.findRenderObject() as RenderBox?;
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile.fromData(bytes, name: safe, mimeType: mime)],
        fileNameOverrides: [safe],
        sharePositionOrigin: box == null
            ? null
            : box.localToGlobal(Offset.zero) & box.size,
      ),
    );
  }
}

Future<void> previewFile(
  BuildContext context,
  String name,
  Uint8List bytes, {
  ErpApi? api,
}) async {
  Widget protect(Widget child) => api == null
      ? child
      : AccessGate(
          api: api,
          revalidate: () async {
            throw const ErpException(
              'Access changed. Close this preview and open the current document again.',
            );
          },
          child: child,
        );
  final extension = name.split('.').last.toLowerCase();
  if (extension == 'pdf') {
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => protect(
          Scaffold(
            appBar: AppBar(title: Text(name)),
            body: PdfPreview(
              build: (_) => bytes,
              pdfFileName: name,
              canChangeOrientation: false,
              canChangePageFormat: false,
              allowSharing: true,
            ),
          ),
        ),
      ),
    );
  } else if (const {'png', 'jpg', 'jpeg', 'gif', 'webp'}.contains(extension)) {
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => protect(
          Scaffold(
            appBar: AppBar(
              title: Text(name),
              actions: [
                IconButton(
                  tooltip: 'Save file',
                  onPressed: () => saveOrShareFile(context, name, bytes),
                  icon: const Icon(Icons.save_alt),
                ),
              ],
            ),
            body: Center(
              child: InteractiveViewer(
                child: Image.memory(
                  bytes,
                  errorBuilder: (_, _, _) =>
                      const Text('This image could not be displayed.'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  } else {
    await saveOrShareFile(context, name, bytes);
  }
}

import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:barcode/barcode.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import 'design.dart';
import 'file_actions.dart';
import 'native_barcode.dart';

typedef OpenFieldFile = Future<void> Function(
  BuildContext context,
  String field,
  String? table,
  String? row,
);

class PrivateFileField extends StatefulWidget {
  const PrivateFileField({
    super.key,
    required this.label,
    required this.value,
    required this.image,
    required this.editable,
    required this.onChanged,
    this.open,
    this.error,
  });
  final String label;
  final Object? value;
  final bool image, editable;
  final ValueChanged<Object?> onChanged;
  final Future<void> Function()? open;
  final String? error;
  @override
  State<PrivateFileField> createState() => _PrivateFileFieldState();
}

class _PrivateFileFieldState extends State<PrivateFileField> {
  String? error;
  bool busy = false;
  Future<void> act(Future<void> Function() perform) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await perform();
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> choose() async {
    const images = XTypeGroup(
      label: 'Images',
      extensions: ['png', 'jpg', 'jpeg', 'webp', 'gif'],
      uniformTypeIdentifiers: [
        'public.png',
        'public.jpeg',
        'org.webmproject.webp',
        'com.compuserve.gif',
      ],
      mimeTypes: ['image/png', 'image/jpeg', 'image/webp', 'image/gif'],
    );
    final file = await openFile(
      acceptedTypeGroups: widget.image ? [images] : [],
    );
    if (file == null || !mounted || !widget.editable) return;
    if (await file.length() > 5000000) {
      throw const FormatException('Choose a file up to 5 MB.');
    }
    final bytes = await file.readAsBytes();
    if (bytes.isEmpty || bytes.length > 5000000) {
      throw const FormatException('Choose a nonempty file up to 5 MB.');
    }
    if (mounted && widget.editable) {
      widget.onChanged({'filename': file.name, 'content': base64Encode(bytes)});
    }
  }

  @override
  Widget build(BuildContext context) {
    final value = widget.value;
    final pending = value is Map ? value : null;
    final exists = pending != null || value is String && value.isNotEmpty;
    return InputDecorator(
      decoration: InputDecoration(
        labelText: widget.label,
        errorText: error ?? widget.error,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (exists)
            Text(
              pending?['filename'] ?? value.toString().split('/').last,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          if (pending != null) const Text('Ready to save privately'),
          Wrap(
            spacing: 6,
            children: [
              if (widget.editable)
                TextButton.icon(
                  onPressed: busy ? null : () => act(choose),
                  icon: const Icon(Icons.attach_file),
                  label: Text(
                    exists
                        ? 'Replace'
                        : widget.image
                        ? 'Choose image'
                        : 'Choose file',
                  ),
                ),
              if (exists && (pending != null || widget.open != null))
                TextButton(
                  onPressed: busy
                      ? null
                      : () => act(() async {
                          if (pending != null) {
                            await previewFile(
                              context,
                              pending['filename'] as String,
                              base64Decode(pending['content'] as String),
                            );
                          } else {
                            await widget.open!();
                          }
                        }),
                  child: const Text('Open file'),
                ),
              if (exists && widget.editable)
                IconButton(
                  tooltip: 'Clear file',
                  onPressed: busy ? null : () => widget.onChanged(''),
                  icon: const Icon(Icons.close),
                ),
            ],
          ),
          if (!exists && !widget.editable) const Text('No file'),
        ],
      ),
    );
  }
}

class SignatureField extends StatelessWidget {
  const SignatureField({
    super.key,
    required this.label,
    required this.value,
    required this.editable,
    required this.onChanged,
    this.error,
  });
  final String label;
  final String? value, error;
  final bool editable;
  final ValueChanged<String> onChanged;
  @override
  Widget build(BuildContext context) {
    final present = value?.isNotEmpty == true;
    Uint8List? bytes;
    if (present &&
        value!.startsWith('data:image/') &&
        value!.length < 7000000) {
      try {
        bytes = UriData.parse(value!).contentAsBytes();
      } on FormatException {
        bytes = null;
      }
    }
    return InputDecorator(
      decoration: InputDecoration(labelText: label, errorText: error),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (bytes != null)
            Image.memory(
              bytes,
              height: 78,
              fit: BoxFit.contain,
              semanticLabel: 'Saved signature',
              errorBuilder: (_, _, _) =>
                  const Text('Signature preview unavailable.'),
            )
          else if (present)
            const Text('Signature preview unavailable.')
          else if (!editable)
            const Text('No signature'),
          if (editable)
            Wrap(
              children: [
                TextButton.icon(
                  icon: const Icon(Icons.draw_outlined),
                  label: Text(present ? 'Replace signature' : 'Add signature'),
                  onPressed: () async {
                    final image = await showDialog<String>(
                      context: context,
                      builder: (_) => const _SignaturePad(),
                    );
                    if (image != null && context.mounted) onChanged(image);
                  },
                ),
                if (present)
                  IconButton(
                    tooltip: 'Clear signature',
                    icon: const Icon(Icons.close),
                    onPressed: () => onChanged(''),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _SignaturePad extends StatefulWidget {
  const _SignaturePad();
  @override
  State<_SignaturePad> createState() => _SignaturePadState();
}

class _SignaturePadState extends State<_SignaturePad> {
  final lines = <List<Offset>>[];
  bool saving = false;
  String? error;
  @override
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    title: const Text('Draw signature'),
    content: SizedBox(
      width: 500,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AspectRatio(
            aspectRatio: 2.5,
            child: Builder(
              builder: (c) {
                Offset normalized(Offset point) {
                  final size = (c.findRenderObject() as RenderBox).size;
                  return Offset(
                    (point.dx / size.width).clamp(0, 1),
                    (point.dy / size.height).clamp(0, 1),
                  );
                }

                return Semantics(
                  label: 'Draw with a finger, pen or mouse',
                  child: GestureDetector(
                    key: const ValueKey('signature-pad'),
                    behavior: HitTestBehavior.opaque,
                    onPanDown: saving
                        ? null
                        : (d) => setState(
                            () => lines.add([normalized(d.localPosition)]),
                          ),
                    onPanUpdate: saving
                        ? null
                        : (d) => setState(
                            () => lines.last.add(normalized(d.localPosition)),
                          ),
                    child: CustomPaint(painter: _Ink(lines)),
                  ),
                );
              },
            ),
          ),
          if (error != null) Text(error!),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: saving ? null : () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      TextButton(
        onPressed: saving || lines.isEmpty ? null : () => setState(lines.clear),
        child: const Text('Clear drawing'),
      ),
      FilledButton(
        onPressed: saving || lines.isEmpty ? null : save,
        child: const Text('Use signature'),
      ),
    ],
  );

  Future<void> save() async {
    setState(() => saving = true);
    try {
      final recorder = ui.PictureRecorder();
      _Ink(lines).paint(Canvas(recorder), const Size(800, 320));
      final picture = recorder.endRecording();
      final image = await picture.toImage(800, 320);
      picture.dispose();
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (data == null) throw StateError('Could not encode signature.');
      if (mounted) {
        Navigator.pop(
          context,
          'data:image/png;base64,${base64Encode(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes))}',
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          saving = false;
          error = 'Could not capture your signature. Try again.';
        });
      }
    }
  }
}

class _Ink extends CustomPainter {
  _Ink(this.lines);
  final List<List<Offset>> lines;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawColor(Colors.white, BlendMode.src);
    final ink = Paint()
      ..color = WorkspaceTheme.ink
      ..strokeWidth = size.width / 200
      ..strokeCap = StrokeCap.round;
    Offset at(Offset p) => Offset(p.dx * size.width, p.dy * size.height);
    for (final line in lines) {
      if (line.length == 1) {
        canvas.drawCircle(at(line.first), ink.strokeWidth / 2, ink);
      }
      for (var i = 1; i < line.length; i++) {
        canvas.drawLine(at(line[i - 1]), at(line[i]), ink);
      }
    }
  }

  @override
  bool shouldRepaint(_Ink old) => true;
}

class BarcodePreview extends StatelessWidget {
  const BarcodePreview({super.key, required this.value, required this.options});
  final String value, options;
  @override
  Widget build(BuildContext context) {
    if (value.isEmpty || value.length > 256) return const SizedBox.shrink();
    try {
      final bars = barcodeFormat(options, value)
          .make(value, width: 300, height: 45, drawText: false)
          .whereType<BarcodeBar>()
          .where((r) => r.black)
          .map((r) => Rect.fromLTWH(r.left, r.top, r.width, r.height))
          .toList();
      return Semantics(
        label: 'Barcode $value',
        child: Container(
          color: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
          child: SizedBox(
            width: 300,
            height: 45,
            child: CustomPaint(painter: _Bars(bars)),
          ),
        ),
      );
    } on Exception {
      return const SizedBox.shrink();
    }
  }
}

class _Bars extends CustomPainter {
  _Bars(this.bars);
  final List<Rect> bars;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 300, size.height / 45);
    final ink = Paint()
      ..color = Colors.black
      ..isAntiAlias = false;
    for (final bar in bars) {
      canvas.drawRect(bar, ink);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_Bars old) => true;
}

import 'dart:typed_data';
import 'dart:ui' as ui show ImmutableBuffer, ImageDescriptor;

import 'package:file_selector/file_selector.dart';

class InvoiceLogoService {
  const InvoiceLogoService();
  Future<Uint8List?> pick() async {
    const types = XTypeGroup(
      label: 'PNG or JPEG image',
      extensions: ['png', 'jpg', 'jpeg'],
      uniformTypeIdentifiers: ['public.png', 'public.jpeg'],
      mimeTypes: ['image/png', 'image/jpeg'],
    );
    final file = await openFile(acceptedTypeGroups: [types]);
    if (file == null) return null;
    const limit = 2 * 1024 * 1024;
    if (await file.length() > limit) {
      throw const FormatException('Choose a PNG or JPEG up to 2 MB.');
    }
    final bytes = await file.readAsBytes();
    if (bytes.length > limit || bytes.length < 8) {
      throw const FormatException('Choose a PNG or JPEG up to 2 MB.');
    }
    final png =
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4e &&
        bytes[3] == 0x47;
    final jpg = bytes[0] == 0xff && bytes[1] == 0xd8 && bytes[2] == 0xff;
    if (!png && !jpg) {
      throw const FormatException('Choose a PNG or JPEG image.');
    }
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    try {
      final info = await ui.ImageDescriptor.encoded(buffer);
      try {
        if (info.width > 4096 ||
            info.height > 4096 ||
            info.width * info.height > 8000000) {
          throw const FormatException(
            'Use a logo up to 4096 pixels per side and 8 megapixels.',
          );
        }
      } finally {
        info.dispose();
      }
    } finally {
      buffer.dispose();
    }
    return bytes;
  }
}

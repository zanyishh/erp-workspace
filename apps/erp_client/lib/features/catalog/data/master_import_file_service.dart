import 'package:file_selector/file_selector.dart';

import '../models/catalog_models.dart';

class MasterImportFileService {
  Future<ImportFile?> choose({void Function(String)? selected}) async {
    final file = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(
          label: 'CSV',
          extensions: ['csv'],
          mimeTypes: ['text/csv', 'application/csv'],
          uniformTypeIdentifiers: ['public.comma-separated-values-text'],
        ),
      ],
    );
    if (file == null) {
      return null;
    }
    selected?.call(file.name);
    if (await file.length() > masterImportMaxBytes) {
      throw const FormatException('Choose a CSV file of up to 256 KB.');
    }
    return ImportFile(file.name, await file.readAsBytes());
  }
}

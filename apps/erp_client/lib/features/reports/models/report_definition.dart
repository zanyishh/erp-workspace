import '../../../core/models/native_models.dart';
import 'report_values.dart';

class ReportDefinition {
  ReportDefinition.fromJson(Map<String, dynamic> value)
    : _data = immutableReportMap(value),
      defaults = immutableReportMap(
        objectMap(value['defaults'] ?? <String, dynamic>{}),
      ),
      reference = value['reference'] as String,
      canExport = enabled(value['can_export']);
  final Map<String, dynamic> _data, defaults;
  final String reference;
  final bool canExport;

  // The shared schema API is mutable; callers receive an isolated projection.
  NativeSchema get schema => NativeSchema.fromJson(_data);
}

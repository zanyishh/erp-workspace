import '../../../core/models/json_values.dart';

Map<String, dynamic> immutableReportMap(Map<String, dynamic> value) =>
    immutableJsonMap(value);

Map<String, dynamic> copyReportMap(Map<String, dynamic> value) =>
    copyJsonMap(value);

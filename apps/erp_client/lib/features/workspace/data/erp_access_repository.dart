import '../../../core/models/access_source.dart';
import '../../../erp_api.dart' show ErpApi;
import 'access_repository.dart';

class ErpAccessRepository implements AccessRepository {
  ErpAccessRepository(this._api);
  final ErpApi _api;
  @override
  AccessSource get source => _api;
  @override
  void addListener(void Function() listener) =>
      _api.addAccessListener(listener);
  @override
  void removeListener(void Function() listener) =>
      _api.removeAccessListener(listener);
}

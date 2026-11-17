import '../../../core/models/access_source.dart';

abstract class AccessRepository {
  AccessSource get source;
  void addListener(void Function() listener);
  void removeListener(void Function() listener);
}

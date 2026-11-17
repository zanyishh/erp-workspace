/// Read-only access identity. Widgets cannot use this port to make API calls.
abstract class AccessSource {
  String get account;
  int get accessRevision;
  bool get accessReady;
}

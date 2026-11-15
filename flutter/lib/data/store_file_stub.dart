// The web has no files: every key stays in shared_preferences (store.dart).
class BigValues {
  static Future<BigValues?> open(Set<String> keys) async => null;
  String? get(String key) => null;
  void put(String key, String? value) {}
  Iterable<String> get keys => const [];
  Future<void> reload() async {}
}

import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

class LocalStore {
  static const _snapshotKey = 'jinshi.snapshot.v1';

  Future<PersistedSnapshot> load() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_snapshotKey);
    return PersistedSnapshot.fromJsonString(value);
  }

  Future<void> save(PersistedSnapshot snapshot) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_snapshotKey, snapshot.toJsonString());
  }
}

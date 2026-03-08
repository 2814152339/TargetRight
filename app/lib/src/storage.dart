import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

const appSnapshotStorageKey = 'animal_park.snapshot.v2';

class LocalStore {
  Future<AppSnapshot> load() async {
    final prefs = await SharedPreferences.getInstance();
    return AppSnapshot.fromJsonString(prefs.getString(appSnapshotStorageKey));
  }

  Future<void> save(AppSnapshot snapshot) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(appSnapshotStorageKey, snapshot.toJsonString());
  }
}

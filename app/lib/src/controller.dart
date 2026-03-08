import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'logic.dart';
import 'models.dart';
import 'notifications.dart';
import 'storage.dart';

final localStoreProvider = Provider<LocalStore>((ref) => LocalStore());
final notificationServiceProvider = Provider<NotificationService>(
  (ref) => NotificationService(),
);

final appControllerProvider = StateNotifierProvider<AppController, AppState>((
  ref,
) {
  return AppController(
    store: ref.read(localStoreProvider),
    notifications: ref.read(notificationServiceProvider),
  );
});

class AppState {
  const AppState({
    required this.initialized,
    required this.snapshot,
    required this.now,
  });

  factory AppState.initial() {
    return AppState(
      initialized: false,
      snapshot: AppSnapshot.initial(),
      now: DateTime.now(),
    );
  }

  final bool initialized;
  final AppSnapshot snapshot;
  final DateTime now;

  String get todayKey => dayKey(now);
  CheckInStatus? get todayStatus => snapshot.dailyRecords[todayKey];
  AnimalState get selectedAnimal =>
      snapshot.animals[snapshot.selectedAnimalId] ??
      const AnimalState(id: 'cat', owned: true, moodPercent: 0);

  List<AnimalState> get ownedAnimals {
    return animalCatalog
        .map((item) => snapshot.animals[item.id]!)
        .where((item) => item.owned)
        .toList();
  }

  AppState copyWith({bool? initialized, AppSnapshot? snapshot, DateTime? now}) {
    return AppState(
      initialized: initialized ?? this.initialized,
      snapshot: snapshot ?? this.snapshot,
      now: now ?? this.now,
    );
  }
}

class AppController extends StateNotifier<AppState> {
  AppController({
    required LocalStore store,
    required NotificationService notifications,
  }) : _store = store,
       _notifications = notifications,
       super(AppState.initial());

  final LocalStore _store;
  final NotificationService _notifications;
  Timer? _ticker;

  Future<void> initialize() async {
    if (state.initialized) {
      return;
    }

    final snapshot = await _store.load();
    state = state.copyWith(
      initialized: true,
      snapshot: snapshot,
      now: DateTime.now(),
    );

    await _notifications.initialize(_handleReminderAction);
    await _notifications.scheduleDailyReminder(
      hour: snapshot.reminderHour,
      minute: snapshot.reminderMinute,
    );
    _startTicker();
  }

  Future<void> markTodayDone() async {
    final updated = applyDailyCheckIn(
      state.snapshot,
      now: DateTime.now(),
      status: CheckInStatus.done,
    );
    await _setSnapshot(updated);
  }

  Future<void> markTodayMissed() async {
    final updated = applyDailyCheckIn(
      state.snapshot,
      now: DateTime.now(),
      status: CheckInStatus.missed,
    );
    await _setSnapshot(updated);
  }

  Future<void> feedSelectedAnimal() async {
    final updated = consumeFeedChance(state.snapshot);
    await _setSnapshot(updated);
  }

  Future<void> selectAnimal(String animalId) async {
    final animal = state.snapshot.animals[animalId];
    if (animal == null || !animal.owned) {
      return;
    }
    final updated = state.snapshot.copyWith(selectedAnimalId: animalId);
    await _setSnapshot(updated);
  }

  Future<bool> buyAnimal(String animalId) async {
    final updated = purchaseAnimal(state.snapshot, animalId);
    if (identical(updated, state.snapshot)) {
      return false;
    }
    await _setSnapshot(updated);
    return true;
  }

  Future<void> setReminderTime(TimeOfDay time) async {
    final updated = state.snapshot.copyWith(
      reminderHour: time.hour,
      reminderMinute: time.minute,
    );
    await _setSnapshot(updated);
    await _notifications.scheduleDailyReminder(
      hour: time.hour,
      minute: time.minute,
    );
  }

  Future<void> _handleReminderAction(ReminderAction action) async {
    if (action == ReminderAction.done) {
      await markTodayDone();
      return;
    }
    if (action == ReminderAction.missed) {
      await markTodayMissed();
    }
  }

  Future<void> _setSnapshot(AppSnapshot snapshot) async {
    state = state.copyWith(snapshot: snapshot, now: DateTime.now());
    await _store.save(snapshot);
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(minutes: 1), (_) {
      state = state.copyWith(now: DateTime.now());
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }
}

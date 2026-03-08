import 'models.dart';

String dayKey(DateTime value) {
  final y = value.year.toString().padLeft(4, '0');
  final m = value.month.toString().padLeft(2, '0');
  final d = value.day.toString().padLeft(2, '0');
  return '$y-$m-$d';
}

bool isYesterday(String? previousDay, DateTime now) {
  if (previousDay == null) {
    return false;
  }
  final yesterday = now.subtract(const Duration(days: 1));
  return previousDay == dayKey(yesterday);
}

AppSnapshot applyDailyCheckIn(
  AppSnapshot snapshot, {
  required DateTime now,
  required CheckInStatus status,
}) {
  final today = dayKey(now);
  if (snapshot.dailyRecords.containsKey(today)) {
    return snapshot;
  }

  final records = Map<String, CheckInStatus>.from(snapshot.dailyRecords)
    ..[today] = status;

  if (status == CheckInStatus.done) {
    final newStreak = isYesterday(snapshot.lastDoneDateKey, now)
        ? snapshot.streakDays + 1
        : 1;
    return snapshot.copyWith(
      dailyRecords: records,
      feedChances: snapshot.feedChances + 1,
      streakDays: newStreak,
      lastDoneDateKey: today,
    );
  }

  return snapshot.copyWith(
    dailyRecords: records,
    streakDays: 0,
    clearLastDoneDateKey: true,
  );
}

AppSnapshot consumeFeedChance(AppSnapshot snapshot) {
  if (snapshot.feedChances <= 0) {
    return snapshot;
  }
  final animal = snapshot.animals[snapshot.selectedAnimalId];
  if (animal == null || !animal.owned) {
    return snapshot;
  }

  var nextMood = animal.moodPercent + 1;
  var nextCoins = snapshot.coins;
  if (nextMood >= 100) {
    nextMood = 0;
    nextCoins += 1;
  }

  final animals = Map<String, AnimalState>.from(snapshot.animals)
    ..[animal.id] = animal.copyWith(moodPercent: nextMood);

  return snapshot.copyWith(
    coins: nextCoins,
    feedChances: snapshot.feedChances - 1,
    animals: animals,
  );
}

AppSnapshot purchaseAnimal(AppSnapshot snapshot, String animalId) {
  final animalDef = animalById(animalId);
  final current = snapshot.animals[animalId];
  if (current == null || current.owned) {
    return snapshot;
  }
  if (snapshot.coins < animalDef.price) {
    return snapshot;
  }

  final animals = Map<String, AnimalState>.from(snapshot.animals)
    ..[animalId] = current.copyWith(owned: true);

  return snapshot.copyWith(
    coins: snapshot.coins - animalDef.price,
    animals: animals,
  );
}

import 'dart:convert';

enum CheckInStatus { done, missed }

class AnimalDefinition {
  const AnimalDefinition({
    required this.id,
    required this.name,
    required this.emoji,
    required this.price,
    this.isStarter = false,
  });

  final String id;
  final String name;
  final String emoji;
  final int price;
  final bool isStarter;
}

const animalCatalog = <AnimalDefinition>[
  AnimalDefinition(
    id: 'cat',
    name: '猫咪',
    emoji: '🐱',
    price: 0,
    isStarter: true,
  ),
  AnimalDefinition(id: 'rabbit', name: '兔子', emoji: '🐰', price: 1),
  AnimalDefinition(id: 'dog', name: '狗', emoji: '🐶', price: 6),
  AnimalDefinition(id: 'fox', name: '狐狸', emoji: '🦊', price: 10),
  AnimalDefinition(id: 'bear', name: '熊', emoji: '🐻', price: 20),
  AnimalDefinition(id: 'raccoon', name: '浣熊', emoji: '🦝', price: 30),
];

AnimalDefinition animalById(String id) {
  return animalCatalog.firstWhere((item) => item.id == id);
}

class AnimalState {
  const AnimalState({
    required this.id,
    required this.owned,
    required this.moodPercent,
  });

  final String id;
  final bool owned;
  final int moodPercent;

  AnimalState copyWith({String? id, bool? owned, int? moodPercent}) {
    return AnimalState(
      id: id ?? this.id,
      owned: owned ?? this.owned,
      moodPercent: moodPercent ?? this.moodPercent,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'owned': owned,
      'moodPercent': moodPercent,
    };
  }

  static AnimalState fromJson(Map<String, dynamic> json) {
    return AnimalState(
      id: json['id'] as String,
      owned: json['owned'] as bool? ?? false,
      moodPercent: json['moodPercent'] as int? ?? 0,
    );
  }
}

class AppSnapshot {
  const AppSnapshot({
    required this.coins,
    required this.feedChances,
    required this.streakDays,
    required this.selectedAnimalId,
    required this.reminderHour,
    required this.reminderMinute,
    required this.animals,
    required this.dailyRecords,
    required this.lastDoneDateKey,
  });

  factory AppSnapshot.initial() {
    final animals = <String, AnimalState>{};
    for (final item in animalCatalog) {
      animals[item.id] = AnimalState(
        id: item.id,
        owned: item.isStarter,
        moodPercent: 0,
      );
    }
    return AppSnapshot(
      coins: 0,
      feedChances: 0,
      streakDays: 0,
      selectedAnimalId: 'cat',
      reminderHour: 9,
      reminderMinute: 0,
      animals: animals,
      dailyRecords: const <String, CheckInStatus>{},
      lastDoneDateKey: null,
    );
  }

  final int coins;
  final int feedChances;
  final int streakDays;
  final String selectedAnimalId;
  final int reminderHour;
  final int reminderMinute;
  final Map<String, AnimalState> animals;
  final Map<String, CheckInStatus> dailyRecords;
  final String? lastDoneDateKey;

  AppSnapshot copyWith({
    int? coins,
    int? feedChances,
    int? streakDays,
    String? selectedAnimalId,
    int? reminderHour,
    int? reminderMinute,
    Map<String, AnimalState>? animals,
    Map<String, CheckInStatus>? dailyRecords,
    String? lastDoneDateKey,
    bool clearLastDoneDateKey = false,
  }) {
    return AppSnapshot(
      coins: coins ?? this.coins,
      feedChances: feedChances ?? this.feedChances,
      streakDays: streakDays ?? this.streakDays,
      selectedAnimalId: selectedAnimalId ?? this.selectedAnimalId,
      reminderHour: reminderHour ?? this.reminderHour,
      reminderMinute: reminderMinute ?? this.reminderMinute,
      animals: animals ?? this.animals,
      dailyRecords: dailyRecords ?? this.dailyRecords,
      lastDoneDateKey: clearLastDoneDateKey
          ? null
          : (lastDoneDateKey ?? this.lastDoneDateKey),
    );
  }

  String toJsonString() {
    return jsonEncode(<String, dynamic>{
      'coins': coins,
      'feedChances': feedChances,
      'streakDays': streakDays,
      'selectedAnimalId': selectedAnimalId,
      'reminderHour': reminderHour,
      'reminderMinute': reminderMinute,
      'animals': animals.map((key, value) => MapEntry(key, value.toJson())),
      'dailyRecords': dailyRecords.map(
        (key, value) => MapEntry(key, value.name),
      ),
      'lastDoneDateKey': lastDoneDateKey,
    });
  }

  static AppSnapshot fromJsonString(String? value) {
    if (value == null || value.isEmpty) {
      return AppSnapshot.initial();
    }
    final decoded = jsonDecode(value) as Map<String, dynamic>;
    final animalJson =
        decoded['animals'] as Map<String, dynamic>? ?? <String, dynamic>{};
    final animals = <String, AnimalState>{};
    for (final entry in animalJson.entries) {
      animals[entry.key] = AnimalState.fromJson(
        entry.value as Map<String, dynamic>,
      );
    }

    for (final item in animalCatalog) {
      animals.putIfAbsent(
        item.id,
        () => AnimalState(id: item.id, owned: item.isStarter, moodPercent: 0),
      );
    }

    final recordJson =
        decoded['dailyRecords'] as Map<String, dynamic>? ?? <String, dynamic>{};
    final records = <String, CheckInStatus>{};
    for (final entry in recordJson.entries) {
      records[entry.key] = CheckInStatus.values.firstWhere(
        (status) => status.name == entry.value,
      );
    }

    final selectedAnimalId = decoded['selectedAnimalId'] as String? ?? 'cat';
    final selectedAnimalOwned = animals[selectedAnimalId]?.owned ?? false;

    return AppSnapshot(
      coins: decoded['coins'] as int? ?? 0,
      feedChances: decoded['feedChances'] as int? ?? 0,
      streakDays: decoded['streakDays'] as int? ?? 0,
      selectedAnimalId: selectedAnimalOwned ? selectedAnimalId : 'cat',
      reminderHour: decoded['reminderHour'] as int? ?? 9,
      reminderMinute: decoded['reminderMinute'] as int? ?? 0,
      animals: animals,
      dailyRecords: records,
      lastDoneDateKey: decoded['lastDoneDateKey'] as String?,
    );
  }
}

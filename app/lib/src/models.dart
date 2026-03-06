import 'dart:convert';

enum TaskType { single, recurring }

enum CheckInState { done, missed }

enum InteractionTemplate { tree, egg, tower, muscle }

class HabitTask {
  HabitTask({
    required this.id,
    required this.name,
    required this.type,
    required this.createdAt,
    required this.enabled,
    required this.isDual,
    required this.progress,
    required this.interaction,
    this.singleDateTime,
    this.intervalMinutes,
    this.startMinuteOfDay,
    this.endMinuteOfDay,
    this.startDate,
    this.endDate,
    this.colorValue,
  });

  final String id;
  final String name;
  final TaskType type;
  final DateTime createdAt;
  final bool enabled;
  final bool isDual;
  final int progress;
  final InteractionTemplate interaction;

  final DateTime? singleDateTime;
  final int? intervalMinutes;
  final int? startMinuteOfDay;
  final int? endMinuteOfDay;
  final DateTime? startDate;
  final DateTime? endDate;
  final int? colorValue;

  HabitTask copyWith({
    String? id,
    String? name,
    TaskType? type,
    DateTime? createdAt,
    bool? enabled,
    bool? isDual,
    int? progress,
    InteractionTemplate? interaction,
    DateTime? singleDateTime,
    int? intervalMinutes,
    int? startMinuteOfDay,
    int? endMinuteOfDay,
    DateTime? startDate,
    DateTime? endDate,
    int? colorValue,
    bool clearEndDate = false,
  }) {
    return HabitTask(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      createdAt: createdAt ?? this.createdAt,
      enabled: enabled ?? this.enabled,
      isDual: isDual ?? this.isDual,
      progress: progress ?? this.progress,
      interaction: interaction ?? this.interaction,
      singleDateTime: singleDateTime ?? this.singleDateTime,
      intervalMinutes: intervalMinutes ?? this.intervalMinutes,
      startMinuteOfDay: startMinuteOfDay ?? this.startMinuteOfDay,
      endMinuteOfDay: endMinuteOfDay ?? this.endMinuteOfDay,
      startDate: startDate ?? this.startDate,
      endDate: clearEndDate ? null : (endDate ?? this.endDate),
      colorValue: colorValue ?? this.colorValue,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'name': name,
      'type': type.name,
      'createdAt': createdAt.toIso8601String(),
      'enabled': enabled,
      'isDual': isDual,
      'progress': progress,
      'interaction': interaction.name,
      'singleDateTime': singleDateTime?.toIso8601String(),
      'intervalMinutes': intervalMinutes,
      'startMinuteOfDay': startMinuteOfDay,
      'endMinuteOfDay': endMinuteOfDay,
      'startDate': startDate?.toIso8601String(),
      'endDate': endDate?.toIso8601String(),
      'colorValue': colorValue,
    };
  }

  static HabitTask fromJson(Map<String, dynamic> json) {
    return HabitTask(
      id: json['id'] as String,
      name: json['name'] as String,
      type: TaskType.values.firstWhere((e) => e.name == json['type']),
      createdAt: DateTime.parse(json['createdAt'] as String),
      enabled: json['enabled'] as bool? ?? true,
      isDual: json['isDual'] as bool? ?? false,
      progress: json['progress'] as int? ?? 0,
      interaction: InteractionTemplate.values.firstWhere(
        (e) =>
            e.name ==
            (json['interaction'] as String? ?? InteractionTemplate.tree.name),
      ),
      singleDateTime: _parseDate(json['singleDateTime']),
      intervalMinutes: json['intervalMinutes'] as int?,
      startMinuteOfDay: json['startMinuteOfDay'] as int?,
      endMinuteOfDay: json['endMinuteOfDay'] as int?,
      startDate: _parseDate(json['startDate']),
      endDate: _parseDate(json['endDate']),
      colorValue: json['colorValue'] as int?,
    );
  }
}

class CheckInRecord {
  CheckInRecord({
    required this.pointId,
    required this.taskId,
    required this.plannedTime,
    required this.updatedAt,
    this.yourState,
    this.partnerState,
  });

  final String pointId;
  final String taskId;
  final DateTime plannedTime;
  final DateTime updatedAt;
  final CheckInState? yourState;
  final CheckInState? partnerState;

  bool isFinalDone(bool isDual) {
    if (!isDual) {
      return yourState == CheckInState.done;
    }
    return yourState == CheckInState.done && partnerState == CheckInState.done;
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'pointId': pointId,
      'taskId': taskId,
      'plannedTime': plannedTime.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'yourState': yourState?.name,
      'partnerState': partnerState?.name,
    };
  }

  static CheckInRecord fromJson(Map<String, dynamic> json) {
    final yourStateName = json['yourState'] as String?;
    final partnerStateName = json['partnerState'] as String?;
    return CheckInRecord(
      pointId: json['pointId'] as String,
      taskId: json['taskId'] as String,
      plannedTime: DateTime.parse(json['plannedTime'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      yourState: yourStateName == null
          ? null
          : CheckInState.values.firstWhere((e) => e.name == yourStateName),
      partnerState: partnerStateName == null
          ? null
          : CheckInState.values.firstWhere((e) => e.name == partnerStateName),
    );
  }
}

class PersistedSnapshot {
  PersistedSnapshot({
    required this.tasks,
    required this.checkIns,
    required this.isVip,
    required this.featureFlagDualOpen,
  });

  final List<HabitTask> tasks;
  final List<CheckInRecord> checkIns;
  final bool isVip;
  final bool featureFlagDualOpen;

  String toJsonString() {
    return jsonEncode(<String, dynamic>{
      'tasks': tasks.map((e) => e.toJson()).toList(),
      'checkIns': checkIns.map((e) => e.toJson()).toList(),
      'isVip': isVip,
      'featureFlagDualOpen': featureFlagDualOpen,
    });
  }

  static PersistedSnapshot fromJsonString(String? value) {
    if (value == null || value.isEmpty) {
      return PersistedSnapshot(
        tasks: <HabitTask>[],
        checkIns: <CheckInRecord>[],
        isVip: false,
        featureFlagDualOpen: true,
      );
    }
    final decoded = jsonDecode(value) as Map<String, dynamic>;
    final tasks = (decoded['tasks'] as List<dynamic>? ?? <dynamic>[])
        .map((e) => HabitTask.fromJson(e as Map<String, dynamic>))
        .toList();
    final checkIns = (decoded['checkIns'] as List<dynamic>? ?? <dynamic>[])
        .map((e) => CheckInRecord.fromJson(e as Map<String, dynamic>))
        .toList();
    return PersistedSnapshot(
      tasks: tasks,
      checkIns: checkIns,
      isVip: decoded['isVip'] as bool? ?? false,
      featureFlagDualOpen: decoded['featureFlagDualOpen'] as bool? ?? true,
    );
  }
}

DateTime? _parseDate(Object? value) {
  if (value == null) {
    return null;
  }
  return DateTime.parse(value as String);
}

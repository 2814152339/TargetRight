import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';

import 'controller.dart';
import 'logic.dart';
import 'models.dart';

class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  int _tabIndex = 0;

  @override
  void initState() {
    super.initState();
    Future<void>.microtask(
      () => ref.read(appControllerProvider.notifier).initialize(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appControllerProvider);
    if (!state.initialized) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final pages = <Widget>[
      HomeTab(onCreateTask: () => _openTaskEditor(context)),
      const CalendarTab(),
      MeTab(
        onCreateTask: () => _openTaskEditor(context),
        onEditTask: (task) => _openTaskEditor(context, initial: task),
      ),
    ];

    return Scaffold(
      body: SafeArea(
        child: IndexedStack(index: _tabIndex, children: pages),
      ),
      floatingActionButton: _tabIndex == 1
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _openTaskEditor(context),
              icon: const Icon(Icons.add),
              label: const Text('新建提醒'),
            ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tabIndex,
        onDestinationSelected: (index) => setState(() => _tabIndex = index),
        destinations: const <NavigationDestination>[
          NavigationDestination(icon: Icon(Icons.home_outlined), label: '首页'),
          NavigationDestination(icon: Icon(Icons.calendar_month), label: '日历'),
          NavigationDestination(icon: Icon(Icons.person_outline), label: '我的'),
        ],
      ),
    );
  }

  Future<void> _openTaskEditor(
    BuildContext context, {
    HabitTask? initial,
  }) async {
    final canChooseDual = ref
        .read(appControllerProvider)
        .canChooseDualWhenCreate;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) =>
          TaskFormSheet(initial: initial, canChooseDual: canChooseDual),
    );
  }
}

class HomeTab extends ConsumerWidget {
  const HomeTab({super.key, required this.onCreateTask});

  final VoidCallback onCreateTask;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appControllerProvider);
    final recurringTasks = state.recurringTasks;
    if (recurringTasks.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(Icons.inbox, size: 48),
              const SizedBox(height: 12),
              const Text('还没有循环任务'),
              const SizedBox(height: 8),
              const Text(
                '首页只展示循环多频次任务。先新建一个提醒开始打卡。',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: onCreateTask,
                icon: const Icon(Icons.add),
                label: const Text('新建提醒'),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: <Widget>[
        const SizedBox(height: 12),
        const Text(
          '循环任务',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 10),
        Expanded(
          child: PageView.builder(
            controller: PageController(viewportFraction: 0.9),
            itemCount: recurringTasks.length,
            itemBuilder: (context, index) {
              final task = recurringTasks[index];
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                child: _TaskCard(task: task),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _TaskCard extends ConsumerWidget {
  const _TaskCard({required this.task});

  final HabitTask task;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appControllerProvider);
    final controller = ref.read(appControllerProvider.notifier);

    final interaction = interactionForTask(task);
    final pendingTime = earliestPendingPoint(task, state.checkIns, state.now);
    final nextTime = nextPointAfterNow(task, state.now);
    final pendingRecord = pendingTime == null
        ? null
        : state.checkIns[reminderPointId(task.id, pendingTime)];

    final yourStatus = pendingRecord?.yourState;
    final partnerStatus = pendingRecord?.partnerState;
    final canCheckIn = pendingTime != null && yourStatus == null;

    return Card(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    task.name,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Switch(
                  value: task.enabled,
                  onChanged: (value) =>
                      controller.setTaskEnabled(task.id, value),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Center(
              child: Text(
                interaction.emoji,
                style: const TextStyle(fontSize: 64),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '${interaction.stageName} ${interaction.current}/${interaction.target}',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            LinearProgressIndicator(value: interaction.ratio),
            const SizedBox(height: 12),
            Text('下一次提醒：${_formatDateTimeOrDash(nextTime)}'),
            const SizedBox(height: 8),
            if (pendingTime != null)
              Text('待确认提醒点：${DateFormat('HH:mm').format(pendingTime)}')
            else
              const Text('当前没有待确认提醒点'),
            if (task.isDual && pendingTime != null) ...<Widget>[
              const SizedBox(height: 6),
              Text(
                '你：${stateLabel(yourStatus)}  TA：${stateLabel(partnerStatus)}  最终：${finalStatusLabel(finalStatusForPoint(task, pendingRecord))}',
              ),
            ],
            const SizedBox(height: 12),
            if (canCheckIn)
              Row(
                children: <Widget>[
                  Expanded(
                    child: FilledButton(
                      onPressed: () => controller.checkInYourself(
                        taskId: task.id,
                        plannedTime: pendingTime,
                        result: CheckInState.done,
                      ),
                      child: const Text('已完成'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => controller.checkInYourself(
                        taskId: task.id,
                        plannedTime: pendingTime,
                        result: CheckInState.missed,
                      ),
                      child: const Text('未完成'),
                    ),
                  ),
                ],
              ),
            if (task.isDual && pendingTime != null) ...<Widget>[
              const SizedBox(height: 8),
              Row(
                children: <Widget>[
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => controller.checkInPartner(
                        taskId: task.id,
                        plannedTime: pendingTime,
                        result: CheckInState.done,
                      ),
                      child: const Text('模拟 TA 已完成'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => controller.checkInPartner(
                        taskId: task.id,
                        plannedTime: pendingTime,
                        result: CheckInState.missed,
                      ),
                      child: const Text('模拟 TA 未完成'),
                    ),
                  ),
                ],
              ),
            ],
            if (task.isDual) ...<Widget>[
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: () async {
                  final link = controller.createInviteLink(task.id);
                  await Clipboard.setData(ClipboardData(text: link));
                  if (context.mounted) {
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(const SnackBar(content: Text('邀请链接已复制')));
                  }
                },
                icon: const Icon(Icons.share),
                label: const Text('复制邀请链接'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class CalendarTab extends ConsumerStatefulWidget {
  const CalendarTab({super.key});

  @override
  ConsumerState<CalendarTab> createState() => _CalendarTabState();
}

class _CalendarTabState extends ConsumerState<CalendarTab> {
  DateTime _focusedDay = DateTime.now();
  DateTime _selectedDay = DateTime.now();

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appControllerProvider);
    final controller = ref.read(appControllerProvider.notifier);
    final activeTasks = state.tasks.where((task) => task.enabled).toList();
    final todayEntries = dayEntries(activeTasks, state.checkIns, _selectedDay);

    return Column(
      children: <Widget>[
        TableCalendar<DayPlanEntry>(
          firstDay: DateTime(2020, 1, 1),
          lastDay: DateTime(2035, 12, 31),
          focusedDay: _focusedDay,
          selectedDayPredicate: (day) => isSameDate(day, _selectedDay),
          eventLoader: (day) => dayEntries(activeTasks, state.checkIns, day),
          calendarFormat: CalendarFormat.month,
          onDaySelected: (selectedDay, focusedDay) {
            setState(() {
              _selectedDay = selectedDay;
              _focusedDay = focusedDay;
            });
          },
          onPageChanged: (focusedDay) => _focusedDay = focusedDay,
          calendarBuilders: CalendarBuilders<DayPlanEntry>(
            markerBuilder: (context, day, entries) {
              if (entries.isEmpty) {
                return null;
              }
              final doneCount = entries
                  .where(
                    (entry) =>
                        finalStatusForPoint(entry.task, entry.record) ==
                        FinalStatus.done,
                  )
                  .length;
              return Positioned(
                bottom: 4,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: doneCount == entries.length
                        ? Colors.green.shade600
                        : Colors.orange.shade600,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$doneCount/${entries.length}',
                    style: const TextStyle(color: Colors.white, fontSize: 10),
                  ),
                ),
              );
            },
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: todayEntries.isEmpty
              ? const Center(child: Text('当天没有计划提醒点'))
              : ListView.separated(
                  itemCount: todayEntries.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final item = todayEntries[index];
                    final now = state.now;
                    final canCheckNow =
                        !item.time.isAfter(now) &&
                        item.record?.yourState == null;
                    return ListTile(
                      title: Text(
                        '${DateFormat('HH:mm').format(item.time)}  ${item.task.name}',
                      ),
                      subtitle: Text(
                        item.task.isDual
                            ? '你:${stateLabel(item.record?.yourState)} TA:${stateLabel(item.record?.partnerState)} 最终:${finalStatusLabel(finalStatusForPoint(item.task, item.record))}'
                            : '状态：${finalStatusLabel(finalStatusForPoint(item.task, item.record))}',
                      ),
                      trailing: Wrap(
                        spacing: 6,
                        children: <Widget>[
                          if (canCheckNow)
                            IconButton(
                              tooltip: '已完成',
                              icon: const Icon(
                                Icons.check_circle,
                                color: Colors.green,
                              ),
                              onPressed: () => controller.checkInYourself(
                                taskId: item.task.id,
                                plannedTime: item.time,
                                result: CheckInState.done,
                              ),
                            ),
                          if (canCheckNow)
                            IconButton(
                              tooltip: '未完成',
                              icon: const Icon(
                                Icons.cancel,
                                color: Colors.redAccent,
                              ),
                              onPressed: () => controller.checkInYourself(
                                taskId: item.task.id,
                                plannedTime: item.time,
                                result: CheckInState.missed,
                              ),
                            ),
                          if (item.task.isDual && !item.time.isAfter(now))
                            IconButton(
                              tooltip: '模拟TA已完成',
                              icon: const Icon(Icons.group, color: Colors.blue),
                              onPressed: () => controller.checkInPartner(
                                taskId: item.task.id,
                                plannedTime: item.time,
                                result: CheckInState.done,
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class MeTab extends ConsumerWidget {
  const MeTab({
    super.key,
    required this.onCreateTask,
    required this.onEditTask,
  });

  final VoidCallback onCreateTask;
  final ValueChanged<HabitTask> onEditTask;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appControllerProvider);
    final controller = ref.read(appControllerProvider.notifier);

    return ListView(
      padding: const EdgeInsets.all(12),
      children: <Widget>[
        Card(
          child: Column(
            children: <Widget>[
              SwitchListTile(
                value: state.isVip,
                onChanged: (value) => controller.setVip(value),
                title: const Text('VIP 会员'),
                subtitle: const Text('VIP 可在新建循环任务时选择单人/双人'),
              ),
              SwitchListTile(
                value: state.featureFlagDualOpen,
                onChanged: (value) => controller.setFeatureFlagDualOpen(value),
                title: const Text('Feature Flag：双人全量开放'),
                subtitle: const Text('调试期开启后，非 VIP 也可使用双人创建'),
              ),
              const SizedBox(height: 8),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('非 VIP 情况下，双人入口仅保留在“我的”。'),
                ),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: <Widget>[
            Expanded(
              child: FilledButton.icon(
                onPressed: onCreateTask,
                icon: const Icon(Icons.add),
                label: const Text('新建提醒'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Text('任务管理（共 ${state.tasks.length} 个）'),
          ),
        ),
        const SizedBox(height: 6),
        ...state.tasks.map(
          (task) => Card(
            child: ListTile(
              leading: Icon(
                task.type == TaskType.single ? Icons.event : Icons.repeat,
              ),
              title: Text(task.name),
              subtitle: Text(_taskSubtitle(task)),
              onTap: () => onEditTask(task),
              trailing: PopupMenuButton<String>(
                onSelected: (value) async {
                  if (value == 'edit') {
                    onEditTask(task);
                    return;
                  }
                  if (value == 'delete') {
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (_) => AlertDialog(
                        title: const Text('删除任务'),
                        content: const Text('确认删除该任务及相关打卡记录？'),
                        actions: <Widget>[
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('取消'),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.pop(context, true),
                            child: const Text('删除'),
                          ),
                        ],
                      ),
                    );
                    if (confirmed == true) {
                      await controller.deleteTask(task.id);
                    }
                    return;
                  }
                  if (value == 'dual') {
                    await controller.convertTaskToDual(task.id);
                    return;
                  }
                  if (value == 'share') {
                    final link = controller.createInviteLink(task.id);
                    await Clipboard.setData(ClipboardData(text: link));
                    if (context.mounted) {
                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(const SnackBar(content: Text('邀请链接已复制')));
                    }
                  }
                },
                itemBuilder: (_) {
                  final items = <PopupMenuEntry<String>>[
                    const PopupMenuItem(value: 'edit', child: Text('编辑')),
                    const PopupMenuItem(value: 'delete', child: Text('删除')),
                  ];
                  if (task.type == TaskType.recurring && !task.isDual) {
                    items.add(
                      const PopupMenuItem(value: 'dual', child: Text('转为双人')),
                    );
                  }
                  if (task.type == TaskType.recurring && task.isDual) {
                    items.add(
                      const PopupMenuItem(
                        value: 'share',
                        child: Text('复制邀请链接'),
                      ),
                    );
                  }
                  return items;
                },
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class TaskFormSheet extends ConsumerStatefulWidget {
  const TaskFormSheet({super.key, this.initial, required this.canChooseDual});

  final HabitTask? initial;
  final bool canChooseDual;

  @override
  ConsumerState<TaskFormSheet> createState() => _TaskFormSheetState();
}

class _TaskFormSheetState extends ConsumerState<TaskFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _intervalController;

  late TaskType _type;
  late bool _isDual;
  late InteractionTemplate _interaction;

  late DateTime _singleDate;
  late TimeOfDay _singleTime;

  late TimeOfDay _windowStart;
  late TimeOfDay _windowEnd;
  late DateTime _startDate;
  DateTime? _endDate;
  bool _hasEndDate = false;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _nameController = TextEditingController(text: initial?.name ?? '');
    _intervalController = TextEditingController(
      text: (initial?.intervalMinutes ?? 120).toString(),
    );
    _type = initial?.type ?? TaskType.recurring;
    _isDual = initial?.isDual ?? false;
    _interaction = initial?.interaction ?? InteractionTemplate.tree;

    final single =
        initial?.singleDateTime ??
        DateTime.now().add(const Duration(minutes: 30));
    _singleDate = DateTime(single.year, single.month, single.day);
    _singleTime = TimeOfDay(hour: single.hour, minute: single.minute);

    final startMinute = initial?.startMinuteOfDay ?? (9 * 60);
    final endMinute = initial?.endMinuteOfDay ?? (21 * 60);
    _windowStart = _timeFromMinutes(startMinute);
    _windowEnd = _timeFromMinutes(endMinute);
    _startDate = dateOnly(initial?.startDate ?? DateTime.now());
    _endDate = initial?.endDate == null ? null : dateOnly(initial!.endDate!);
    _hasEndDate = _endDate != null;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _intervalController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.initial != null;
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                isEditing ? '编辑任务' : '新建任务',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: '任务名称',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return '请输入任务名称';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<TaskType>(
                initialValue: _type,
                decoration: const InputDecoration(
                  labelText: '任务类型',
                  border: OutlineInputBorder(),
                ),
                items: const <DropdownMenuItem<TaskType>>[
                  DropdownMenuItem(value: TaskType.single, child: Text('单次')),
                  DropdownMenuItem(
                    value: TaskType.recurring,
                    child: Text('循环'),
                  ),
                ],
                onChanged: (value) {
                  if (value == null) {
                    return;
                  }
                  setState(() => _type = value);
                },
              ),
              const SizedBox(height: 12),
              if (_type == TaskType.single) ...<Widget>[
                _DateTimePickerTile(
                  title: '日期',
                  value: DateFormat('yyyy-MM-dd').format(_singleDate),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      firstDate: DateTime(2020, 1, 1),
                      lastDate: DateTime(2035, 12, 31),
                      initialDate: _singleDate,
                    );
                    if (picked != null) {
                      setState(() => _singleDate = picked);
                    }
                  },
                ),
                const SizedBox(height: 8),
                _DateTimePickerTile(
                  title: '时间',
                  value: _singleTime.format(context),
                  onTap: () async {
                    final picked = await showTimePicker(
                      context: context,
                      initialTime: _singleTime,
                    );
                    if (picked != null) {
                      setState(() => _singleTime = picked);
                    }
                  },
                ),
              ],
              if (_type == TaskType.recurring) ...<Widget>[
                TextFormField(
                  controller: _intervalController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: '间隔分钟',
                    hintText: '例如 120',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    final interval = int.tryParse(value ?? '');
                    if (interval == null || interval <= 0) {
                      return '请输入大于 0 的间隔分钟';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 8),
                _DateTimePickerTile(
                  title: '每日开始时间',
                  value: _windowStart.format(context),
                  onTap: () async {
                    final picked = await showTimePicker(
                      context: context,
                      initialTime: _windowStart,
                    );
                    if (picked != null) {
                      setState(() => _windowStart = picked);
                    }
                  },
                ),
                const SizedBox(height: 8),
                _DateTimePickerTile(
                  title: '每日结束时间',
                  value: _windowEnd.format(context),
                  onTap: () async {
                    final picked = await showTimePicker(
                      context: context,
                      initialTime: _windowEnd,
                    );
                    if (picked != null) {
                      setState(() => _windowEnd = picked);
                    }
                  },
                ),
                const SizedBox(height: 8),
                _DateTimePickerTile(
                  title: '开始日期',
                  value: DateFormat('yyyy-MM-dd').format(_startDate),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      firstDate: DateTime(2020, 1, 1),
                      lastDate: DateTime(2035, 12, 31),
                      initialDate: _startDate,
                    );
                    if (picked != null) {
                      setState(() => _startDate = picked);
                    }
                  },
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  value: _hasEndDate,
                  title: const Text('设置结束日期'),
                  onChanged: (value) => setState(() {
                    _hasEndDate = value;
                    if (!value) {
                      _endDate = null;
                    } else {
                      _endDate ??= _startDate.add(const Duration(days: 30));
                    }
                  }),
                ),
                if (_hasEndDate)
                  _DateTimePickerTile(
                    title: '结束日期',
                    value: _endDate == null
                        ? '--'
                        : DateFormat('yyyy-MM-dd').format(_endDate!),
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        firstDate: _startDate,
                        lastDate: DateTime(2035, 12, 31),
                        initialDate: _endDate ?? _startDate,
                      );
                      if (picked != null) {
                        setState(() => _endDate = picked);
                      }
                    },
                  ),
                const SizedBox(height: 8),
                DropdownButtonFormField<InteractionTemplate>(
                  initialValue: _interaction,
                  decoration: const InputDecoration(
                    labelText: '互动模板',
                    border: OutlineInputBorder(),
                  ),
                  items: const <DropdownMenuItem<InteractionTemplate>>[
                    DropdownMenuItem(
                      value: InteractionTemplate.tree,
                      child: Text('种子 - 果树'),
                    ),
                    DropdownMenuItem(
                      value: InteractionTemplate.egg,
                      child: Text('鸡蛋 - 大鸡'),
                    ),
                    DropdownMenuItem(
                      value: InteractionTemplate.tower,
                      child: Text('地基 - 摩天楼'),
                    ),
                    DropdownMenuItem(
                      value: InteractionTemplate.muscle,
                      child: Text('瘦子 - 肌肉男'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => _interaction = value);
                    }
                  },
                ),
                const SizedBox(height: 8),
                if (widget.canChooseDual)
                  SwitchListTile(
                    value: _isDual,
                    title: const Text('双人共同打卡'),
                    subtitle: const Text('双方都“已完成”才会增长互动进度'),
                    onChanged: (value) => setState(() => _isDual = value),
                  )
                else
                  const Text('当前账号不是 VIP，且未开启调试开关，新建流程不展示双人选项'),
              ],
              const SizedBox(height: 16),
              Row(
                children: <Widget>[
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('取消'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      onPressed: _submit,
                      child: Text(isEditing ? '保存' : '创建'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    if (_type == TaskType.recurring) {
      final startMinute = _minutesOfDay(_windowStart);
      final endMinute = _minutesOfDay(_windowEnd);
      if (endMinute < startMinute) {
        _showError('每日结束时间必须晚于开始时间');
        return;
      }
      if (_hasEndDate && _endDate != null && _endDate!.isBefore(_startDate)) {
        _showError('结束日期不能早于开始日期');
        return;
      }
    }

    final initial = widget.initial;
    final now = DateTime.now();
    final id = initial?.id ?? 'task_${now.microsecondsSinceEpoch}';
    final interval = int.tryParse(_intervalController.text.trim());

    final task = HabitTask(
      id: id,
      name: _nameController.text.trim(),
      type: _type,
      createdAt: initial?.createdAt ?? now,
      enabled: initial?.enabled ?? true,
      isDual: _type == TaskType.recurring
          ? (widget.canChooseDual ? _isDual : false)
          : false,
      progress: initial?.progress ?? 0,
      interaction: _interaction,
      singleDateTime: _type == TaskType.single
          ? DateTime(
              _singleDate.year,
              _singleDate.month,
              _singleDate.day,
              _singleTime.hour,
              _singleTime.minute,
            )
          : null,
      intervalMinutes: _type == TaskType.recurring ? interval : null,
      startMinuteOfDay: _type == TaskType.recurring
          ? _minutesOfDay(_windowStart)
          : null,
      endMinuteOfDay: _type == TaskType.recurring
          ? _minutesOfDay(_windowEnd)
          : null,
      startDate: _type == TaskType.recurring ? dateOnly(_startDate) : null,
      endDate: _type == TaskType.recurring && _hasEndDate
          ? dateOnly(_endDate!)
          : null,
    );

    await ref.read(appControllerProvider.notifier).upsertTask(task);
    if (mounted) {
      Navigator.pop(context);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _DateTimePickerTile extends StatelessWidget {
  const _DateTimePickerTile({
    required this.title,
    required this.value,
    required this.onTap,
  });

  final String title;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Ink(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade400),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: <Widget>[
            Expanded(child: Text(title)),
            Text(value),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right),
          ],
        ),
      ),
    );
  }
}

String _formatDateTimeOrDash(DateTime? time) {
  if (time == null) {
    return '--';
  }
  return DateFormat('MM-dd HH:mm').format(time);
}

String _taskSubtitle(HabitTask task) {
  if (task.type == TaskType.single) {
    final when = task.singleDateTime;
    return when == null
        ? '单次提醒'
        : '单次：${DateFormat('yyyy-MM-dd HH:mm').format(when)}';
  }
  final start = _formatMinuteOfDay(task.startMinuteOfDay ?? 0);
  final end = _formatMinuteOfDay(task.endMinuteOfDay ?? 0);
  final interval = task.intervalMinutes ?? 0;
  final dual = task.isDual ? '双人' : '单人';
  return '循环：每 $interval 分钟，$start-$end，$dual';
}

String _formatMinuteOfDay(int minute) {
  final h = (minute ~/ 60).toString().padLeft(2, '0');
  final m = (minute % 60).toString().padLeft(2, '0');
  return '$h:$m';
}

int _minutesOfDay(TimeOfDay time) => time.hour * 60 + time.minute;

TimeOfDay _timeFromMinutes(int minute) {
  final clamped = minute.clamp(0, 23 * 60 + 59);
  return TimeOfDay(hour: clamped ~/ 60, minute: clamped % 60);
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'controller.dart';
import 'models.dart';

class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  int _tab = 0;

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

    final pages = <Widget>[const HomePage(), const StorePage()];

    return Scaffold(
      body: SafeArea(child: pages[_tab]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (value) => setState(() => _tab = value),
        destinations: const <NavigationDestination>[
          NavigationDestination(icon: Icon(Icons.pets_outlined), label: '首页'),
          NavigationDestination(
            icon: Icon(Icons.storefront_outlined),
            label: '商店',
          ),
        ],
      ),
    );
  }
}

class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appControllerProvider);
    final controller = ref.read(appControllerProvider.notifier);
    final snapshot = state.snapshot;
    final selectedAnimal = snapshot.animals[snapshot.selectedAnimalId]!;
    final selectedDef = animalById(selectedAnimal.id);
    final feedEnabled = snapshot.feedChances > 0;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        Text(
          '${snapshot.streakDays} Days',
          style: const TextStyle(fontSize: 42, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 4),
        Text(
          "${selectedDef.name}的 Animal Park",
          style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF7E3),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: const Color(0xFF8C6A43), width: 2),
          ),
          child: Column(
            children: <Widget>[
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: state.ownedAnimals.map((item) {
                  final def = animalById(item.id);
                  final selected = item.id == snapshot.selectedAnimalId;
                  return GestureDetector(
                    onTap: () => controller.selectAnimal(item.id),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      width: 64,
                      height: 64,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: selected
                            ? const Color(0xFFFFEBA8)
                            : const Color(0xFFF5F1DC),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: selected
                              ? const Color(0xFF2875D8)
                              : const Color(0xFF8C6A43),
                          width: selected ? 3 : 1.5,
                        ),
                      ),
                      child: Text(
                        def.emoji,
                        style: const TextStyle(fontSize: 34),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
              Text(
                '${selectedDef.name} 心情 ${selectedAnimal.moodPercent}%',
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(30),
                child: LinearProgressIndicator(
                  value: selectedAnimal.moodPercent / 100,
                  minHeight: 12,
                  color: const Color(0xFF4DAA57),
                  backgroundColor: const Color(0xFFE0D7BF),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text(
          '喂食机会：${snapshot.feedChances}    金币：${snapshot.coins}',
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 56,
          child: ElevatedButton(
            onPressed: feedEnabled
                ? () async {
                    await controller.feedSelectedAnimal();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('已喂食 +1% 心情')),
                      );
                    }
                  }
                : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: feedEnabled
                  ? const Color(0xFF2D8BFF)
                  : Colors.grey.shade400,
              disabledBackgroundColor: Colors.grey.shade400,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(30),
                side: const BorderSide(color: Color(0xFF2D4F7B), width: 2),
              ),
            ),
            child: const Text(
              'Feed Animals',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700),
            ),
          ),
        ),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFF6F6F6),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE0E0E0)),
          ),
          child: Column(
            children: <Widget>[
              Row(
                children: <Widget>[
                  const Expanded(
                    child: Text(
                      '今日打卡状态',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Text(_todayStatusText(state.todayStatus)),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: <Widget>[
                  Expanded(
                    child: FilledButton(
                      onPressed: state.todayStatus == null
                          ? () => controller.markTodayDone()
                          : null,
                      child: const Text('今日已完成'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: state.todayStatus == null
                          ? () => controller.markTodayMissed()
                          : null,
                      child: const Text('今日未完成'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: <Widget>[
                  const Text('提醒时间'),
                  const Spacer(),
                  Text(
                    _formatTime(snapshot.reminderHour, snapshot.reminderMinute),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: () async {
                      final picked = await showTimePicker(
                        context: context,
                        initialTime: TimeOfDay(
                          hour: snapshot.reminderHour,
                          minute: snapshot.reminderMinute,
                        ),
                      );
                      if (picked != null) {
                        await controller.setReminderTime(picked);
                      }
                    },
                    child: const Text('修改'),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          '提示：iOS 锁屏通知可直接点“已完成/未完成”记录，不用先进入 App。',
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

class StorePage extends ConsumerWidget {
  const StorePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appControllerProvider);
    final controller = ref.read(appControllerProvider.notifier);
    final snapshot = state.snapshot;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 2),
          child: Text(
            'STORE',
            style: TextStyle(fontSize: 38, fontWeight: FontWeight.w800),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            '当前金币：${snapshot.coins}',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
          ),
        ),
        const SizedBox(height: 10),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(12),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 0.86,
            ),
            itemCount: animalCatalog.length,
            itemBuilder: (context, index) {
              final def = animalCatalog[index];
              final animal = snapshot.animals[def.id]!;
              final owned = animal.owned;
              final selected = snapshot.selectedAnimalId == def.id;
              final canBuy = snapshot.coins >= def.price;

              return Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF7E3),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: selected
                        ? const Color(0xFF2D8BFF)
                        : const Color(0xFF8C6A43),
                    width: selected ? 3 : 2,
                  ),
                ),
                child: Column(
                  children: <Widget>[
                    const SizedBox(height: 4),
                    Text(def.emoji, style: const TextStyle(fontSize: 58)),
                    const SizedBox(height: 6),
                    Text(
                      def.name,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text('心情 ${animal.moodPercent}%'),
                    const Spacer(),
                    if (owned)
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: () => controller.selectAnimal(def.id),
                          child: Text(selected ? '使用中' : '设为当前'),
                        ),
                      )
                    else
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: canBuy
                              ? () async {
                                  final ok = await controller.buyAnimal(def.id);
                                  if (!context.mounted) {
                                    return;
                                  }
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        ok ? '购买成功：${def.name}' : '金币不足',
                                      ),
                                    ),
                                  );
                                }
                              : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: canBuy
                                ? const Color(0xFF2D8BFF)
                                : Colors.grey.shade400,
                          ),
                          child: Text('购买 ${def.price} 金币'),
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

String _todayStatusText(CheckInStatus? status) {
  switch (status) {
    case CheckInStatus.done:
      return '已完成';
    case CheckInStatus.missed:
      return '未完成';
    case null:
      return '未记录';
  }
}

String _formatTime(int hour, int minute) {
  final h = hour.toString().padLeft(2, '0');
  final m = minute.toString().padLeft(2, '0');
  return '$h:$m';
}

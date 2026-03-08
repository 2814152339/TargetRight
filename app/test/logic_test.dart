import 'package:flutter_test/flutter_test.dart';
import 'package:jinshi_checkin/src/logic.dart';
import 'package:jinshi_checkin/src/models.dart';

void main() {
  test('完成一次任务会增加 1 次喂食机会，并更新连胜天数', () {
    final base = AppSnapshot.initial();
    final day1 = DateTime(2026, 3, 8, 9);
    final day2 = DateTime(2026, 3, 9, 9);

    final afterDay1 = applyDailyCheckIn(
      base,
      now: day1,
      status: CheckInStatus.done,
    );
    final afterDay2 = applyDailyCheckIn(
      afterDay1,
      now: day2,
      status: CheckInStatus.done,
    );

    expect(afterDay1.feedChances, 1);
    expect(afterDay1.streakDays, 1);
    expect(afterDay2.feedChances, 2);
    expect(afterDay2.streakDays, 2);
  });

  test('喂食让心情 +1%，达到 100% 时奖励 1 金币并重置为 0%', () {
    final base = AppSnapshot.initial();
    final cat = base.animals['cat']!;
    final nearTarget = base.copyWith(
      feedChances: 1,
      animals: <String, AnimalState>{
        ...base.animals,
        'cat': cat.copyWith(moodPercent: 99),
      },
    );

    final updated = consumeFeedChance(nearTarget);
    final updatedCat = updated.animals['cat']!;

    expect(updated.feedChances, 0);
    expect(updated.coins, 1);
    expect(updatedCat.moodPercent, 0);
  });

  test('商店购买会扣金币并解锁动物', () {
    final base = AppSnapshot.initial().copyWith(coins: 6);
    final updated = purchaseAnimal(base, 'dog');

    expect(updated.coins, 0);
    expect(updated.animals['dog']!.owned, isTrue);
  });
}

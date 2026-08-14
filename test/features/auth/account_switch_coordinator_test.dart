import 'package:flutter_test/flutter_test.dart';

import 'package:trainflow_ai/features/auth/application/account_switch_coordinator.dart';

void main() {
  test('先清理健康队列与本地健康数据，再执行数据库原子换绑', () async {
    final List<String> calls = <String>[];
    final AccountSwitchCoordinator coordinator = AccountSwitchCoordinator(
      clearPendingHealthQueue: () async => calls.add('queue'),
      confirmDatabaseAccountSwitch: () async {
        calls.add('database');
        return true;
      },
      resetInMemoryState: () => calls.add('reset'),
    );

    await coordinator.confirm();

    expect(calls, <String>['queue', 'database', 'reset']);
  });

  test('健康队列清理失败时不得继续数据库换绑', () async {
    bool databaseCalled = false;
    final AccountSwitchCoordinator coordinator = AccountSwitchCoordinator(
      clearPendingHealthQueue: () async {
        throw StateError('本地健康数据清理失败');
      },
      confirmDatabaseAccountSwitch: () async {
        databaseCalled = true;
        return true;
      },
      resetInMemoryState: () {},
    );

    await expectLater(coordinator.confirm(), throwsStateError);
    expect(databaseCalled, isFalse);
  });

  test('数据库原子换绑失败时不刷新内存状态', () async {
    final List<String> calls = <String>[];
    final AccountSwitchCoordinator coordinator = AccountSwitchCoordinator(
      clearPendingHealthQueue: () async => calls.add('queue'),
      confirmDatabaseAccountSwitch: () async {
        calls.add('database');
        return false;
      },
      resetInMemoryState: () => calls.add('reset'),
    );

    await expectLater(coordinator.confirm(), throwsStateError);
    expect(calls, <String>['queue', 'database']);
  });
}

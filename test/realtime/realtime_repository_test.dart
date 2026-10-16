import 'dart:async';

import 'package:backend_sdk/backend_sdk.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_data_backend.dart';
import '../support/fakes.dart';
import '../support/test_helpers.dart';

void main() {
  late FakeRealtimeBackend provider;
  late RealtimeRepository repository;
  late ProductsRepository products;

  setUp(() {
    provider = FakeRealtimeBackend();
    repository = RealtimeRepository(backend: provider);
    products = buildProductsRepository(
      backend: FakeDataBackend(),
      realtime: repository,
    );
  });

  tearDown(() async {
    await repository.dispose();
  });

  BackendRecord record(String id, {String name = 'Phone'}) => <String, dynamic>{
        'id': id,
        'name': name,
        'price': 10,
        'stock': 1,
        'is_active': true,
      };

  group('RealtimeRepository - subscription lifecycle', () {
    test('watch opens exactly one provider channel', () {
      final watcher = products.watchRealtime();
      unawaited(watcher.ready);

      expect(repository.activeSubscriptionCount, 1);
    });

    test('identical watchers share one channel', () {
      final first = products.watchRealtime();
      final second = products.watchRealtime();
      unawaited(first.ready);
      unawaited(second.ready);

      expect(provider.subscribeCalls, 1);
      expect(repository.activeSubscriptionCount, 1);
      expect(provider.openChannels, 1);
    });

    test('different filters open separate channels', () {
      final a = products.watchRealtime(filters: const {'category_id': 'a'});
      final b = products.watchRealtime(filters: const {'category_id': 'b'});
      unawaited(a.ready);
      unawaited(b.ready);

      expect(provider.subscribeCalls, 2);
      expect(repository.activeSubscriptionCount, 2);
    });

    test('hasActiveSubscription reports the open channel', () {
      products.watchRealtime();
      expect(
        repository.hasActiveSubscription(resource: BackendResource.products),
        isTrue,
      );
      expect(
        repository.hasActiveSubscription(resource: BackendResource.users),
        isFalse,
      );
    });
  });

  group('RealtimeRepository - typed events', () {
    test('an insert is decoded into a Product', () async {
      final watcher = products.watchRealtime();
      final events = <RealtimeEvent<Product>>[];
      final subscription = watcher.events.listen(events.add);
      await watcher.ready;

      provider.emit(BackendResource.products, record: record('p1'));
      await pumpEventQueue();

      expect(events, hasLength(1));
      expect(events.single.type, RealtimeEventType.inserted);
      expect(events.single.newData?.id, 'p1');
      expect(events.single.newData?.name, 'Phone');
      await subscription.cancel();
    });

    test('an update carries the new record', () async {
      final watcher = products.watchRealtime();
      final events = <RealtimeEvent<Product>>[];
      final subscription = watcher.events.listen(events.add);
      await watcher.ready;

      provider.emit(
        BackendResource.products,
        record: record('p1', name: 'Updated'),
        type: RealtimeEventType.updated,
      );
      await pumpEventQueue();

      expect(events.single.type, RealtimeEventType.updated);
      expect(events.single.newData?.name, 'Updated');
      await subscription.cancel();
    });

    test('a delete carries the old record', () async {
      final watcher = products.watchRealtime();
      final events = <RealtimeEvent<Product>>[];
      final subscription = watcher.events.listen(events.add);
      await watcher.ready;

      provider.emit(
        BackendResource.products,
        record: const <String, dynamic>{},
        oldRecord: record('p1'),
        type: RealtimeEventType.deleted,
      );
      await pumpEventQueue();

      expect(events.single.type, RealtimeEventType.deleted);
      expect(events.single.newData, isNull);
      expect(events.single.oldData?.id, 'p1');
      await subscription.cancel();
    });

    test('an unmappable payload is skipped, not fatal', () async {
      final watcher = products.watchRealtime();
      final events = <RealtimeEvent<Product>>[];
      final subscription = watcher.events.listen(events.add);
      await watcher.ready;

      // A row missing its required columns cannot become a Product.
      provider.emit(
        BackendResource.products,
        record: const <String, dynamic>{'id': 'broken'},
      );
      provider.emit(BackendResource.products, record: record('p1'));
      await pumpEventQueue();

      expect(events, hasLength(1));
      expect(events.single.newData?.id, 'p1');
      expect(watcher.lastFailure?.type, BackendErrorType.realtime);
      await subscription.cancel();
    });

    test('the wrong model type yields an empty stream, not a TypeError',
        () async {
      final watcher = repository.watch<String>(
        resource: BackendResource.products,
      );
      final events = <RealtimeEvent<String>>[];
      final subscription = watcher.events.listen(events.add);
      await watcher.ready;

      provider.emit(BackendResource.products, record: record('p1'));
      await pumpEventQueue();

      expect(events, isEmpty);
      await subscription.cancel();
    });
  });

  group('RealtimeRepository - cleanup', () {
    test('disposing the last watcher closes the provider channel', () async {
      final watcher = products.watchRealtime();
      await watcher.ready;

      await watcher.dispose();

      expect(provider.unsubscribeCalls, 1);
      expect(provider.openChannels, 0);
      expect(repository.activeSubscriptionCount, 0);
      expect(watcher.isActive, isFalse);
    });

    test('the channel survives until the last watcher disposes', () async {
      final first = products.watchRealtime();
      final second = products.watchRealtime();
      await first.ready;

      await first.dispose();
      expect(provider.unsubscribeCalls, 0);
      expect(repository.activeSubscriptionCount, 1);

      await second.dispose();
      expect(provider.unsubscribeCalls, 1);
      expect(repository.activeSubscriptionCount, 0);
    });

    test('dispose is idempotent', () async {
      final watcher = products.watchRealtime();
      await watcher.ready;

      await watcher.dispose();
      await watcher.dispose();
      await watcher.dispose();

      expect(provider.unsubscribeCalls, 1);
    });

    test('disposing the repository closes every channel', () async {
      products.watchRealtime();
      products.watchRealtime(filters: const {'category_id': 'a'});
      await pumpEventQueue();

      expect(repository.activeSubscriptionCount, 2);

      await repository.dispose();

      expect(provider.openChannels, 0);
      expect(provider.disposeCalls, 1);
      expect(repository.activeSubscriptionCount, 0);
    });

    test('disposing the repository twice is safe', () async {
      products.watchRealtime();
      await repository.dispose();
      await repository.dispose();

      expect(provider.disposeCalls, 1);
    });

    test('a new watcher after disposal gets a fresh channel', () async {
      final first = products.watchRealtime();
      await first.ready;
      await first.dispose();

      final second = products.watchRealtime();
      await second.ready;

      expect(provider.subscribeCalls, 2);
      expect(repository.activeSubscriptionCount, 1);
    });
  });

  group('RealtimeRepository - failures', () {
    test('an invalid filter field is rejected without opening a channel', () {
      final watcher = repository.watch<Product>(
        resource: BackendResource.products,
        filters: const {'id)or(1': 'x'},
      );

      expect(watcher.isActive, isFalse);
      expect(watcher.lastFailure?.type, BackendErrorType.validation);
      expect(provider.subscribeCalls, 0);
    });

    test('an unsupported filter value type is rejected', () {
      final watcher = repository.watch<Product>(
        resource: BackendResource.products,
        filters: const {
          'category_id': <int>[1, 2]
        },
      );

      expect(watcher.lastFailure?.type, BackendErrorType.validation);
    });

    test('a resource without a registered decoder is rejected', () {
      final watcher = repository.watch<Product>(
        resource: BackendResource.users,
      );

      expect(watcher.lastFailure?.type, BackendErrorType.realtime);
      expect(watcher.lastFailure?.message, contains('No realtime decoder'));
    });

    test('a subscribe failure is recorded, not thrown to the caller', () async {
      provider.subscribeFailure = BackendErrorClassifier.build(
        type: BackendErrorType.network,
        message: 'socket closed',
      );

      final watcher = products.watchRealtime();
      await watcher.ready;

      expect(watcher.lastFailure?.type, BackendErrorType.network);
      expect(watcher.isActive, isTrue);
    });

    test('a rejected watcher exposes an inert stream', () async {
      final watcher = repository.watch<Product>(
        resource: BackendResource.users,
      );

      final events = <RealtimeEvent<Product>>[];
      await for (final event in watcher.events) {
        events.add(event);
      }

      expect(events, isEmpty);
    });
  });

  group('RealtimeResource', () {
    test('the channel name is deterministic for the same filters', () {
      final a = RealtimeResource(
        resource: BackendResource.products,
        filters: const {'a': 1, 'b': 2},
      );
      final b = RealtimeResource(
        resource: BackendResource.products,
        filters: const {'b': 2, 'a': 1},
      );

      expect(a.channelName, b.channelName);
    });

    test('the channel name differs for different filters', () {
      final a = RealtimeResource(
        resource: BackendResource.products,
        filters: const {'a': 1},
      );
      final b = RealtimeResource(
        resource: BackendResource.products,
        filters: const {'a': 2},
      );

      expect(a.channelName, isNot(b.channelName));
    });

    test('validate rejects unsafe field names', () {
      expect(
        RealtimeResource.validate(const {'a,or(b)': 'x'}),
        isNotNull,
      );
      expect(RealtimeResource.validate(const {'category_id': 'x'}), isNull);
    });
  });

  group('RealtimeEvent', () {
    test('exposes payload presence helpers', () {
      const event = RealtimeEvent<int>(
        type: RealtimeEventType.updated,
        oldData: 1,
        newData: 2,
      );

      expect(event.hasOldData, isTrue);
      expect(event.hasNewData, isTrue);
      expect(event.toString(), isNot(contains('oldData: 1')));
    });
  });
}

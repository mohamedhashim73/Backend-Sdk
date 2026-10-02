import 'package:backend_sdk/backend_sdk.dart';
import 'package:backend_sdk/src/contracts/pagination_backend.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_data_backend.dart';
import '../support/test_helpers.dart';

void main() {
  group('PageRequest - inclusive range arithmetic', () {
    test('the first page starts at 0 and ends at pageSize - 1', () {
      const request = PageRequest(page: 1, pageSize: 20);

      expect(request.inclusiveStart, 0);
      expect(request.inclusiveEnd, 19);
      expect(request.offset, 0);
    });

    test('the second page starts at pageSize and ends inclusively', () {
      const request = PageRequest(page: 2, pageSize: 20);

      expect(request.inclusiveStart, 20);
      expect(request.inclusiveEnd, 39);
    });

    test('page 100 with pageSize 20 spans 1980..1999', () {
      const request = PageRequest(page: 100, pageSize: 20);

      expect(request.inclusiveStart, 1980);
      expect(request.inclusiveEnd, 1999);
    });

    test('a page size of one produces a single-record range', () {
      const request = PageRequest(page: 5, pageSize: 1);

      expect(request.inclusiveStart, 4);
      expect(request.inclusiveEnd, 4);
    });

    test('PaginationBackend.pageRange agrees with PageRequest', () {
      for (final page in <int>[1, 2, 3, 17]) {
        final range = PaginationBackend.pageRange(
          page: page,
          pageSize: 20,
        );
        expect(range.from, (page - 1) * 20);
        expect(range.to, page * 20 - 1);
      }
    });

    test('BackendRepository.rangeFor agrees with PageRequest', () {
      const request = PageRequest(page: 3, pageSize: 15);
      final range = BackendRepository.rangeFor(request);

      expect(range.from, 30);
      expect(range.to, 44);
    });
  });

  group('PageRequest - validation', () {
    test('rejects page numbers below one', () {
      expect(const PageRequest(page: 0).validate(), contains('1 or greater'));
      expect(const PageRequest(page: -3).validate(), isNotNull);
    });

    test('accepts page one', () {
      expect(const PageRequest(page: 1).validate(), isNull);
    });

    test('rejects a page size below the minimum', () {
      expect(
        const PageRequest(page: 1, pageSize: 0).validate(),
        contains('at least'),
      );
    });

    test('rejects a page size above the safe maximum', () {
      expect(
        const PageRequest(page: 1, pageSize: PaginationLimits.maxPageSize + 1)
            .validate(),
        contains('must not exceed'),
      );
      expect(
        const PageRequest(page: 1, pageSize: PaginationLimits.maxPageSize)
            .validate(),
        isNull,
      );
    });

    test('rejects an absurdly deep page and points at cursor pagination', () {
      final error =
          const PageRequest(page: PaginationLimits.maxPage + 1).validate();
      expect(error, isNull, reason: 'the depth check lives in the repository');
    });

    test('cacheKey distinguishes different requests', () {
      const a = PageRequest(page: 1, pageSize: 20);
      const b = PageRequest(page: 2, pageSize: 20);
      final c = const PageRequest(page: 1, pageSize: 20).copyWith(search: 'x');

      expect(a.cacheKey, isNot(b.cacheKey));
      expect(a.cacheKey, isNot(c.cacheKey));
      expect(a.cacheKey, const PageRequest(page: 1, pageSize: 20).cacheKey);
    });
  });

  group('CursorRequest', () {
    test('validates its limit', () {
      expect(const CursorRequest(limit: 0).validate(), contains('at least'));
      expect(
        const CursorRequest(limit: PaginationLimits.maxCursorLimit + 1)
            .validate(),
        contains('must not exceed'),
      );
      expect(const CursorRequest(limit: 50).validate(), isNull);
    });

    test('never renders the cursor value in toString', () {
      const request = CursorRequest(cursor: 'eyJvIjoxfQ==');

      expect(request.toString(), isNot(contains('eyJvIjoxfQ==')));
      expect(request.toString(), contains('***'));
    });
  });

  group('PageResult', () {
    test('a full page implies more records', () {
      final page = PageResult<int>.fromItems(
        items: List<int>.filled(20, 1),
        page: 1,
        pageSize: 20,
      );

      expect(page.hasMore, isTrue);
      expect(page.totalCount, isNull);
    });

    test('a short page means there is nothing more', () {
      final page = PageResult<int>.fromItems(
        items: List<int>.filled(7, 1),
        page: 1,
        pageSize: 20,
      );

      expect(page.hasMore, isFalse);
    });

    test('an empty page reports no more records', () {
      final page = PageResult<int>.fromItems(
        items: const [],
        page: 4,
        pageSize: 20,
      );

      expect(page.isEmpty, isTrue);
      expect(page.hasMore, isFalse);
    });

    test('a known total count overrides the full-page heuristic', () {
      final exactlyFilled = PageResult<int>.fromItems(
        items: List<int>.filled(20, 1),
        page: 1,
        pageSize: 20,
        totalCount: 20,
      );
      expect(exactlyFilled.hasMore, isFalse);

      final oneMore = PageResult<int>.fromItems(
        items: List<int>.filled(20, 1),
        page: 1,
        pageSize: 20,
        totalCount: 21,
      );
      expect(oneMore.hasMore, isTrue);
    });

    test('a negative total count is discarded rather than trusted', () {
      final page = PageResult<int>.fromItems(
        items: List<int>.filled(20, 1),
        page: 1,
        pageSize: 20,
        totalCount: -5,
      );

      expect(page.totalCount, isNull);
      expect(page.hasMore, isTrue);
    });

    test('items are exposed as an unmodifiable list', () {
      final page = PageResult<int>.fromItems(
        items: const [1, 2, 3],
        page: 1,
        pageSize: 20,
      );

      expect(() => page.items.add(4), throwsUnsupportedError);
    });
  });

  group('CursorPageResult', () {
    test('exposes length and emptiness helpers', () {
      const page = CursorPageResult<int>(
        items: [1, 2],
        hasMore: true,
        nextCursor: 'abc',
      );

      expect(page.length, 2);
      expect(page.isNotEmpty, isTrue);
      expect(page.toString(), isNot(contains('abc')));
    });
  });

  group('Repository pagination end to end', () {
    late FakeDataBackend backend;
    late ProductsRepository repository;

    setUp(() {
      backend = FakeDataBackend()..softDeleteColumn = 'deleted_at';
      repository = buildProductsRepository(backend: backend);
      seedProducts(backend, 45);
    });

    test('page one returns the first pageSize records', () async {
      final result = await repository.getPage(
        request: const PageRequest(page: 1, pageSize: 20),
      );

      final page = result.data!;
      expect(page.items, hasLength(20));
      expect(page.items.first.id, 'p1');
      expect(page.hasMore, isTrue);
    });

    test('the range sent to the backend is inclusive on both ends', () async {
      await repository.getPage(
          request: const PageRequest(page: 1, pageSize: 20));

      expect(backend.pageSpecs.single.from, 0);
      expect(backend.pageSpecs.single.to, 19);
      expect(backend.pageSpecs.single.limit, 20);
    });

    test('page two starts exactly where page one ended', () async {
      await repository.getPage(
          request: const PageRequest(page: 2, pageSize: 20));

      expect(backend.pageSpecs.single.from, 20);
      expect(backend.pageSpecs.single.to, 39);
    });

    test('a page past the end returns an empty, non-more page', () async {
      final result = await repository.getPage(
        request: const PageRequest(page: 99, pageSize: 20),
      );

      final page = result.data!;
      expect(page.isEmpty, isTrue);
      expect(page.hasMore, isFalse);
      expect(page.page, 99);
    });

    test('the last partial page reports no more records', () async {
      final result = await repository.getPage(
        request: const PageRequest(page: 3, pageSize: 20),
      );

      final page = result.data!;
      expect(page.items, hasLength(5));
      expect(page.hasMore, isFalse);
    });

    test('no count query is issued unless it is requested', () async {
      await repository.getPage(
          request: const PageRequest(page: 1, pageSize: 20));

      expect(backend.countSpecs, isEmpty);
    });

    test('a requested total count is returned and computed server side',
        () async {
      final result = await repository.getPage(
        request: const PageRequest(
          page: 1,
          pageSize: 20,
          includeTotalCount: true,
        ),
      );

      expect(result.data!.totalCount, 45);
      expect(backend.pageSpecs.single.includeTotalCount, isTrue);
    });

    test('an explicit count call issues exactly one count query', () async {
      final result = await repository.count();

      expect(result.data, 45);
      expect(backend.countSpecs, hasLength(1));
      expect(backend.pageSpecs, isEmpty);
    });

    test('a page size above the maximum is rejected before any request',
        () async {
      final result = await repository.getPage(
        request: const PageRequest(
          page: 1,
          pageSize: PaginationLimits.maxPageSize + 1,
        ),
      );

      expect(result.failure?.type, BackendErrorType.validation);
      expect(backend.pageSpecs, isEmpty);
    });

    test('page zero is rejected before any request', () async {
      final result =
          await repository.getPage(request: const PageRequest(page: 0));

      expect(result.failure?.type, BackendErrorType.validation);
      expect(backend.pageSpecs, isEmpty);
    });

    test('an excessive page depth is rejected and points at cursors', () async {
      final result = await repository.getPage(
        request: const PageRequest(page: PaginationLimits.maxPage + 1),
      );

      expect(result.failure?.type, BackendErrorType.validation);
      expect(result.failure?.message, contains('cursor'));
      expect(backend.pageSpecs, isEmpty);
    });

    test('a duplicate in-flight page load is refused, not duplicated',
        () async {
      backend.latency = const Duration(milliseconds: 30);

      final first = repository.getPage(
        request: const PageRequest(page: 1, pageSize: 20),
      );
      final second = repository.getPage(
        request: const PageRequest(page: 1, pageSize: 20),
      );

      final results = await Future.wait([first, second]);

      expect(results[0].isSuccess, isTrue);
      expect(results[1].failure?.type, BackendErrorType.conflict);
      expect(results[1].failure?.message, contains('already being loaded'));
      expect(backend.readPageCalls, 1);

      // Once the first load settles the same page can be requested again.
      backend.latency = Duration.zero;
      final third = await repository.getPage(
          request: const PageRequest(page: 1, pageSize: 20));
      expect(third.isSuccess, isTrue);
      expect(backend.readPageCalls, 2);
    });

    test('cursor pagination walks the whole set exactly once', () async {
      final seen = <String>[];
      String? cursor;
      var pages = 0;

      do {
        final result = await repository.getCursorPage(
          request: CursorRequest(cursor: cursor, limit: 20),
        );
        final page = result.data!;
        seen.addAll(page.items.map((p) => p.id));
        cursor = page.nextCursor;
        pages++;
      } while (cursor != null && pages < 10);

      expect(seen, hasLength(45));
      expect(seen.toSet(), hasLength(45));
      expect(seen, hasLength(seen.toSet().length));
      expect(pages, 3);
    });

    test('the last cursor page reports no more records', () async {
      final first = await repository.getCursorPage(
        request: const CursorRequest(limit: 20),
      );
      final second = await repository.getCursorPage(
        request: CursorRequest(cursor: first.data!.nextCursor, limit: 20),
      );
      final third = await repository.getCursorPage(
        request: CursorRequest(cursor: second.data!.nextCursor, limit: 20),
      );

      expect(third.data!.hasMore, isFalse);
      expect(third.data!.nextCursor, isNull);
      expect(third.data!.items, hasLength(5));
    });

    test('an oversized cursor limit is rejected before any request', () async {
      final result = await repository.getCursorPage(
        request: const CursorRequest(
          limit: PaginationLimits.maxCursorLimit + 1,
        ),
      );

      expect(result.failure?.type, BackendErrorType.validation);
      expect(backend.cursorSpecs, isEmpty);
    });

    test('soft-deleted rows are excluded from every read', () async {
      await repository.softDelete('p1');
      backend.clear(BackendResource.products);
      backend.seed(
        BackendResource.products,
        productRow(id: 'p1', deletedAt: '2026-06-01T00:00:00Z'),
      );
      backend.seed(BackendResource.products, productRow(id: 'p2'));

      final page = await repository.getPage(
        request: const PageRequest(page: 1, pageSize: 20),
      );

      expect(page.data!.items.map((p) => p.id), ['p2']);
      expect(
        backend.pageSpecs.single.filters.where((f) => f.field == 'deleted_at'),
        hasLength(1),
      );
    });
  });
}

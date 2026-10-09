import 'package:backend_sdk/src/errors/backend_error_type.dart';
import 'package:backend_sdk/src/result/backend_result.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_data_backend.dart';

void main() {
  test('decodes an aggregated home-feed RPC response', () async {
    final backend = FakeDataBackend()
      ..rpcResponses['get_home_feed'] = <String, Object?>{
        'featured': <Object?>[
          <String, Object?>{'id': 'story-1', 'title': 'Welcome'},
        ],
        'recommended': <Object?>[
          <String, Object?>{'id': 'story-2', 'title': 'Explore'},
        ],
      };

    final result = await backend.callRpc<HomeFeed>(
      functionName: 'get_home_feed',
      parameters: const <String, Object?>{'locale': 'ar'},
      decoder: HomeFeed.fromJson,
    );

    expect(result, isA<BackendSuccess<HomeFeed>>());
    final feed = (result as BackendSuccess<HomeFeed>).value;
    expect(feed.featured.single.title, 'Welcome');
    expect(feed.recommended.single.id, 'story-2');
  });

  test('rejects unsafe RPC names before dispatch', () async {
    final backend = FakeDataBackend();

    final result = await backend.callRpc<Object?>(
      functionName: 'get_home_feed(); delete',
      decoder: (value) => value,
    );

    expect(result.failure?.type, BackendErrorType.validation);
  });
}

class HomeFeed {
  final List<FeedStory> featured;
  final List<FeedStory> recommended;

  const HomeFeed({required this.featured, required this.recommended});

  factory HomeFeed.fromJson(Object? value) {
    final json = Map<String, Object?>.from(value! as Map);
    return HomeFeed(
      featured: _stories(json['featured']),
      recommended: _stories(json['recommended']),
    );
  }

  static List<FeedStory> _stories(Object? value) => (value! as List)
      .map((item) => FeedStory.fromJson(item))
      .toList(growable: false);
}

class FeedStory {
  final String id;
  final String title;

  const FeedStory({required this.id, required this.title});

  factory FeedStory.fromJson(Object? value) {
    final json = Map<String, Object?>.from(value! as Map);
    return FeedStory(
        id: json['id']! as String, title: json['title']! as String);
  }
}

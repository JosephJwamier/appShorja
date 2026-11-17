import 'package:flutter_test/flutter_test.dart';
import 'package:marketplace_app/models/reel.dart';

void main() {
  test('a comment carries its replies, the seller flag and the mention', () {
    final c = ReelComment.fromJson({
      'id': 1,
      'user_id': 7,
      'username': 'buyer',
      'content': 'بكم؟',
      'created_at': '2026-11-17T10:00:00Z',
      'parent_id': null,
      'is_store_owner': false,
      'replies': [
        {
          'id': 2,
          'user_id': 9,
          'username': 'seller',
          'content': '25 ألف',
          'created_at': '2026-11-17T10:01:00Z',
          'parent_id': 1,
          'is_store_owner': true,
        },
        {
          'id': 3,
          'user_id': 8,
          'username': 'other',
          'content': 'وبالجملة؟',
          'created_at': '2026-11-17T10:02:00Z',
          'parent_id': 1,
          'reply_to_username': 'seller',
        },
      ],
    });

    expect(c.isReply, isFalse);
    expect(c.replies.map((r) => r.id), [2, 3]);
    expect(c.replies.first.isStoreOwner, isTrue);
    expect(c.replies.first.isReply, isTrue);
    expect(c.replies.last.replyToUsername, 'seller');
  });

  test('a comment from an older server reads as a plain top-level one', () {
    final c = ReelComment.fromJson({
      'id': 1,
      'user_id': 7,
      'username': 'buyer',
      'content': 'hi',
      'created_at': '2026-11-17T10:00:00Z',
    });
    expect(c.isReply, isFalse);
    expect(c.replies, isEmpty);
    expect(c.isStoreOwner, isFalse);
  });
}

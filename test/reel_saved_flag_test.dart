// علمان منطقيان يسكنان نفس البطاقة ويفعلان شيئين مختلفين تماماً:
// `is_liked_by_me` علنيّ ومعه عدّاد، و`is_saved_by_me` خاصّ وبلا عدّاد.
//
// وما يجعلهما خطرين أن `Reel.fromJson` تُرجع `false` عند غياب المفتاح. فخطأ
// حرف واحد في اسم المفتاح، أو نسيانه في `copyWith`، لا يُنتج استثناءً ولا
// تحذيراً من المحلّل — بل زرّ حفظ يبقى فارغاً للأبد بينما الصفّ محفوظ فعلاً
// على الخادم. وهذا بالضبط ما يحرسه هذا الملف: أسماء المفاتيح، واستقلال
// العلمين عن بعضهما.
import 'package:flutter_test/flutter_test.dart';
import 'package:marketplace_app/models/reel.dart';

Map<String, dynamic> reelJson({
  bool? liked,
  bool? saved,
}) =>
    {
      'id': 3,
      'store': {'id': 1, 'name': 'متجر علي', 'owner_username': 'tajir'},
      'caption': 'بضاعة وصلت اليوم',
      'video_url': 'https://cdn.example.com/reels/1/a/video.mp4',
      'thumbnail_url': 'https://cdn.example.com/reels/1/a/thumb.jpg',
      'duration_seconds': 20,
      'view_count': 140,
      'likes_count': 12,
      'comments_count': 3,
      'is_liked_by_me': ?liked,
      'is_saved_by_me': ?saved,
      'status': 'published',
      'created_at': '2026-10-17T09:00:00Z',
    };

void main() {
  group('قراءة العلم من الخادم', () {
    test('is_saved_by_me تُقرأ كما هي', () {
      expect(Reel.fromJson(reelJson(saved: true)).isSavedByMe, isTrue);
      expect(Reel.fromJson(reelJson(saved: false)).isSavedByMe, isFalse);
    });

    test('غياب المفتاح يعني «غير محفوظ» لا انفجاراً', () {
      // الضيف يحصل على بطاقة بلا هذا المفتاح أصلاً في أسوأ الحالات.
      expect(Reel.fromJson(reelJson()).isSavedByMe, isFalse);
    });

    test('العلمان مستقلّان', () {
      final likedOnly = Reel.fromJson(reelJson(liked: true, saved: false));
      expect(likedOnly.isLikedByMe, isTrue);
      expect(likedOnly.isSavedByMe, isFalse);

      final savedOnly = Reel.fromJson(reelJson(liked: false, saved: true));
      expect(savedOnly.isLikedByMe, isFalse);
      expect(savedOnly.isSavedByMe, isTrue);
    });
  });

  group('copyWith', () {
    final reel = Reel.fromJson(reelJson(liked: true, saved: true));

    test('تبديل الحفظ لا يلمس الإعجاب ولا عدّاده', () {
      final unsaved = reel.copyWith(isSavedByMe: false);
      expect(unsaved.isSavedByMe, isFalse);
      expect(unsaved.isLikedByMe, isTrue);
      expect(unsaved.likesCount, 12);
    });

    test('تبديل الإعجاب لا يلمس الحفظ', () {
      // الزرّان متجاوران في نفس العمود؛ لو أسقط أحدهما علم الآخر لظهر
      // ذلك كـ«ضغطت إعجاب فاختفى الحفظ».
      final unliked = reel.copyWith(isLikedByMe: false, likesCount: 11);
      expect(unliked.isSavedByMe, isTrue);
    });

    test('نسخة بلا وسائط تُبقي الحفظ كما هو', () {
      // applyCommentPosted و applyReelUpdate تمرّان بـcopyWith بلا ذكر
      // الحفظ — ولو لم يُحمل، لألغى كل تعليق جديد حفظَ الريل.
      expect(reel.copyWith(commentsCount: 4).isSavedByMe, isTrue);
    });
  });
}

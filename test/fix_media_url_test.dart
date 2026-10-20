// `fixMediaUrl` تمرّ بها كل صورة في التطبيق: صور المنتجات، وصور
// المحادثات، ولقطات الحجز، وتقييمات المنتجات، ودبابيس الخريطة.
//
// كانت تستبدل `localhost` بـ`10.0.2.2` المكتوب بخط اليد — أي بعنوان محاكي
// جهاز المطوّر، في كل نسخة مُوزَّعة. صارت تبني الوجهة من `ApiConfig`.
//
// وأخطر ما يمكن أن تفعله ليس أن تُخطئ الاستبدال، بل أن **تستبدل أكثر مما
// ينبغي**: روابط الريلز تأتي من نطاق Cloudflare R2 المستقلّ، وإعادة بنائها
// على مضيف الـAPI تكسر كل فيديو ومصغّرة في التطبيق.
import 'package:flutter_test/flutter_test.dart';
import 'package:marketplace_app/utils/formatters.dart';

void main() {
  group('ما يُترك كما هو', () {
    test('رابط الإنتاج لا يُمسّ', () {
      const url = 'https://api.shorjeh.com/media/items/1.jpg';
      expect(fixMediaUrl(url), url);
    });

    test('نطاق Cloudflare R2 لا يُمسّ', () {
      // لو أُعيد بناء هذه على مضيف الـAPI لانقطع كل ريل في التطبيق.
      const url = 'https://media.shorjeh.com/reels/2/abc/video.mp4';
      expect(fixMediaUrl(url), url);
    });

    test('أي مضيف آخر لا يُمسّ', () {
      const url = 'https://cdn.example.com/x.png';
      expect(fixMediaUrl(url), url);
    });

    test('مضيف يبدأ بـlocalhost لكنه ليس هو', () {
      // `localhost.example.com` مضيف حقيقي — والنمط مربوط بالحدّ.
      const url = 'https://localhost.example.com/a.png';
      expect(fixMediaUrl(url), url);
    });
  });

  group('ما يُصلَح', () {
    test('localhost بمنفذ', () {
      expect(fixMediaUrl('http://localhost:8000/media/a.jpg'),
          'https://api.shorjeh.com/media/a.jpg');
    });

    test('localhost بلا منفذ', () {
      expect(fixMediaUrl('http://localhost/media/a.jpg'),
          'https://api.shorjeh.com/media/a.jpg');
    });

    test('127.0.0.1', () {
      expect(fixMediaUrl('http://127.0.0.1:8000/media/a.jpg'),
          'https://api.shorjeh.com/media/a.jpg');
    });

    test('عنوان المحاكي نفسه', () {
      expect(fixMediaUrl('http://10.0.2.2:8000/media/a.jpg'),
          'https://api.shorjeh.com/media/a.jpg');
    });

    test('الأول فقط يُستبدل', () {
      // مسار يحمل الكلمة داخله لا يُعاد كتابته مرّتين.
      expect(fixMediaUrl('http://localhost:8000/media/localhost.jpg'),
          'https://api.shorjeh.com/media/localhost.jpg');
    });
  });

  group('المدخلات الفارغة', () {
    test('null يصير نصّاً فارغاً', () => expect(fixMediaUrl(null), ''));
    test('الفارغ يبقى فارغاً', () => expect(fixMediaUrl(''), ''));
  });
}

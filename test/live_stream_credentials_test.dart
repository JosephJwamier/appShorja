// هذه الاعتمادات هي كل ما يملكه التطبيق ليتّصل بخادم البث: لا SDK يُخبره
// بما ينقص، ولا استثناء يُرفع إن أخطأنا اسم مفتاح. خطأ حرف واحد في
// `whep_url` يُنتج `null` صامتاً، فيرى المشاهد «لم يصل عنوان المشاهدة من
// الخادم» إلى الأبد والخادم يرسل العنوان صحيحاً. ولأن `ice_servers` تُمرَّر
// كما هي إلى RTCPeerConnection، فإن تغيير شكلها هنا يكسر المشاهدين الذين
// يحتاجون المرحّل وحدهم — أي أصحاب شبكات الجوّال خلف CGNAT، وهم بالضبط من
// لا نستطيع اختبار حالتهم على مكتبنا.
import 'package:flutter_test/flutter_test.dart';
import 'package:marketplace_app/models/live_session.dart';

Map<String, dynamic> publisherJson() => {
      'provider': 'srs',
      'role': 'publisher',
      'stream_name': 'live_ab12cd34',
      'whip_url': 'https://live.example.com/rtc/v1/whip/?app=live&stream=live_ab12cd34&token=t',
      'ice_servers': [
        {'urls': ['stun:live.example.com:443']},
        {
          'urls': ['turn:live.example.com:443?transport=udp'],
          'username': '1700000000:u7',
          'credential': 'c2VjcmV0',
        },
      ],
      'expires_in': 3600,
    };

Map<String, dynamic> viewerJson() => {
      'provider': 'srs',
      'role': 'subscriber',
      'stream_name': 'live_ab12cd34',
      'whep_url': 'https://live.example.com/rtc/v1/whep/?app=live&stream=live_ab12cd34&token=t',
      'hls_url': 'https://live.example.com/live/live_ab12cd34.m3u8?token=t',
      'ice_servers': const <Map<String, dynamic>>[],
      'expires_in': 3600,
    };

void main() {
  group('أسماء المفاتيح', () {
    test('الباثّ يقرأ عنوان النشر ولا عنوان مشاهدة', () {
      final credentials = LiveStreamCredentials.fromJson(publisherJson());
      expect(credentials.role, 'publisher');
      expect(credentials.streamName, 'live_ab12cd34');
      expect(credentials.whipUrl, contains('/rtc/v1/whip/'));
      expect(credentials.whepUrl, isNull);
      expect(credentials.hlsUrl, isNull);
    });

    test('المشاهد يقرأ الطريقين: WHEP وHLS', () {
      // الثاني ليس زينة: هو الطريق الوحيد لمن تحجب شبكته WebRTC أصلاً.
      final credentials = LiveStreamCredentials.fromJson(viewerJson());
      expect(credentials.whepUrl, contains('/rtc/v1/whep/'));
      expect(credentials.hlsUrl, endsWith('.m3u8?token=t'));
      expect(credentials.whipUrl, isNull);
    });
  });

  group('خوادم ICE', () {
    test('تُمرَّر كما هي بمفاتيح RTCPeerConnection', () {
      final ice = LiveStreamCredentials.fromJson(publisherJson()).iceServers;
      expect(ice, hasLength(2));
      expect(ice.first['urls'], ['stun:live.example.com:443']);
      expect(ice.last['username'], '1700000000:u7');
      expect(ice.last['credential'], 'c2VjcmV0');
    });

    test('غياب المفتاح يعني قائمة فارغة لا انفجاراً', () {
      // خادم بلا مرحّل مضبوط يرسل الاعتمادات بلا هذا المفتاح — والبثّ
      // يعمل دونه لكل من ليس خلف CGNAT، فلا يجوز أن يسقط التطبيق.
      final json = publisherJson()..remove('ice_servers');
      expect(LiveStreamCredentials.fromJson(json).iceServers, isEmpty);
    });
  });

  test('حقل جديد من الخادم لا يكسر نسخة منشورة', () {
    // غلاف الاعتمادات يملكه الخادم؛ إضافة حقل فيه يجب أن تمرّ بصمت على
    // التطبيقات المنصّبة، وإلا لتعذّر تغيير أي شيء في طبقة الوسائط.
    final json = viewerJson()..['dvr_url'] = 'https://live.example.com/dvr.mp4';
    final credentials = LiveStreamCredentials.fromJson(json);
    expect(credentials.whepUrl, isNotNull);
    expect(credentials.expiresIn, 3600);
  });
}

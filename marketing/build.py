"""يبني الكتيّبات الستة: PDF للطباعة + صفحات WebP لكتيّب الويب + صور الصفحات.

    python marketing/build.py            # الكل
    python marketing/build.py c1 m2      # كتيّبات محدّدة

A5 مع نزف ٣ ملم. النصوص والباركود متجهات، فتُطبع حادّة بأي حجم.
"""
import base64, io, os, subprocess, sys
import qrcode, qrcode.image.svg
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, 'out')
BACKEND = os.path.expanduser('~/PycharmProjects/balla/balla/static')
CHROME = r'C:\Program Files\Google\Chrome\Application\chrome.exe'
SITE = 'https://shorjeh.com/f/'

# رمز: (لون الأساس, لون غامق, لون فاتح) — كل كتيّب يُعرف من بعيد بلونه.
THEME = {
    'c1': ('#e4611a', '#7a2c05', '#ffecc9'),
    'c2': ('#24120a', '#120803', '#ffc36b'),
    'c3': ('#f6dcae', '#7a2c05', '#fff8ec'),
    'm1': ('#7a2c05', '#3d1502', '#ffecc9'),
    'm2': ('#c24a10', '#5c1f03', '#ffecc9'),
    'm3': ('#f28a1c', '#4a1c04', '#fff2d9'),
}

BOOKS = {
 'c1': dict(
  title='السوق كلّه<br>في جيبك', sub='متاجر العراق في تطبيق واحد', cta='امسح وحمّل الشورجة',
  s2=('من الشورجة إلى هاتفك', 'السوق الذي تعرفه بأقواسه ومظلّاته وبضاعته، صار يُفتح بلمسة. تصفّح متاجر من محافظات العراق، وقارن، واختر على مهلك.'),
  s3=('ماذا تجد فيه؟', ['ملابس وأحذية', 'هواتف وإلكترونيات', 'أدوات المنزل والمطبخ', 'عطور وإكسسوارات', 'وكل ما يعرضه الباعة']),
  s4='لا تحتاج حساباً لتتصفّح.<br>افتح وانظر.',
  s5=('ثلاث خطوات', [('تصفّح', 'ابحث أو تجوّل بين المتاجر بلا تسجيل.'), ('احجز', 'ثبّت المنتج باسمك بضغطة.'), ('استلم', 'يصلك الطلب وتؤكّد الاستلام من التطبيق.')]),
  s6=('أشياء ستحبّها', [('قدّم عرضك', 'السعر لا يناسبك؟ أرسل عرضاً للبائع.'), ('تابع متجرك', 'يصلك جديده أوّلاً بأوّل.'), ('احفظ ما أعجبك', 'مفضّلتك تنتظرك متى رجعت.'), ('كوبونات المتاجر', 'اجمعها واستعملها عند الحجز.')]),
  s7=('قبل أن تسأل', [('هل التصفّح مجاني؟', 'نعم، وبلا حساب. الحساب يلزم حين تحجز.'), ('أين يصل التوصيل؟', 'إلى محافظات العراق الثماني عشرة، والأجرة تظهر قبل التأكيد.'), ('هل أكلّم البائع؟', 'نعم، بمحادثة داخل التطبيق.')]),
  s8='السوق مفتوح.<br>تفضّل.'),
 'c2': dict(
  title='زايد،<br>وخذها بسعرك', sub='مزادات وبثّ مباشر من متاجر العراق', cta='امسح وادخل المزاد',
  s2=('متعة المزاد، من مكانك', 'قطعة تعجبك، ووقت ينتهي، ومزايدون معك. تتابع السعر وهو يتحرّك، وتقرّر أنت أين تقف.'),
  s3=('على ماذا تزايد؟', ['ساعات وتحف', 'هواتف وأجهزة', 'قطع نادرة', 'بضاعة جديدة ومستعملة', 'وكل ما يعرضه الباعة']),
  s4='السعر أنت<br>من يحدّده.',
  s5=('كيف تزايد؟', [('اختر', 'افتح المزاد وشاهد القطعة وتفاصيلها.'), ('زايد', 'ضع مزايدتك وتابعها لحظة بلحظة.'), ('افرح بها', 'فزت؟ أكمل الحجز وتصل إليك.')]),
  s6=('وأكثر من مزاد', [('بثّ مباشر', 'البائع يعرض وأنت تسأل وتحجز.'), ('ريلز', 'مقاطع قصيرة من المتاجر.'), ('إشعارات', 'نخبرك بما يحدث في مزادك.'), ('تواصل', 'اسأل البائع قبل أن تزايد.')]),
  s7=('قبل أن تسأل', [('هل أحتاج حساباً؟', 'للمشاهدة لا. للمزايدة نعم.'), ('هل أدفع مقدّماً؟', 'قد يطلب المزاد عربون مشاركة يظهر لك قبل أن تزايد.'), ('كيف تصلني القطعة؟', 'بالتوصيل إلى محافظتك، وتتابعها من التطبيق.')]),
  s8='المزاد لا ينتظر.<br>ادخل الآن.'),
 'c3': dict(
  title='اطلبها، وافحصها<br>عند بابك', sub='تسوّق من متاجر العراق وأنت مطمئن', cta='امسح وحمّل الشورجة',
  s2=('لأن الثقة أوّلاً', 'كثيرون يتردّدون قبل الشراء من هاتفهم. لذلك بنينا الشورجة حول سؤال واحد: كيف يطمئن المشتري حتى تصل البضاعة إلى يده؟'),
  s3=('ما الذي يطمئنك؟', ['مبلغك محفوظ حتى تؤكّد', 'أجرة التوصيل معروفة مسبقاً', 'تتبّع الطلب خطوة بخطوة', 'تقييمات من مشترين', 'مركز لحلّ النزاعات']),
  s4='مبلغك لا يصل البائع<br>قبل أن تؤكّد.',
  s5=('رحلة طلبك', [('احجز', 'ثبّت المنتج باسمك.'), ('تابع', 'ترى أين وصل طلبك.'), ('أكّد', 'استلم وافحص، ثم أكّد الاستلام.')]),
  s6=('ادفع كما يناسبك', [('عند الاستلام', 'للمنتجات التي تتوفّر لها الخدمة.'), ('عربون', 'جزء الآن والباقي عند الاستلام.'), ('كامل المبلغ', 'ويبقى محفوظاً حتى تؤكّد.'), ('محفظة', 'رصيدك وحركاته أمامك.')]),
  s7=('قبل أن تسأل', [('لو وصلت مختلفة؟', 'افتح نزاعاً من التطبيق ليراجعه فريقنا.'), ('كم أجرة التوصيل؟', 'تظهر لك محسوبة قبل أن تؤكّد.'), ('إلى أين يصل؟', 'إلى محافظات العراق الثماني عشرة.')]),
  s8='اطلب وأنت<br>مطمئن.'),
 'm1': dict(
  title='متجرك مفتوح<br>لكل العراق', sub='افتح متجرك في الشورجة من هاتفك', cta='امسح وافتح متجرك',
  s2=('زبونك ليس في شارعك فقط', 'محلّك يراه من يمرّ أمامه. ومتجرك في الشورجة يراه من يبحث عن بضاعتك في أي محافظة.'),
  s3=('ماذا يصير عندك؟', ['صفحة متجر باسمك', 'بضاعتك بصورها وأسعارها', 'متابعون يصلهم جديدك', 'محادثة مع الزبون', 'تقييمات تبني سمعتك']),
  s4='متجر لا يُغلق<br>بعد العشاء.',
  s5=('ابدأ اليوم', [('سجّل', 'حساب برقم هاتفك.'), ('افتح متجرك', 'اسمه وصورته وموقعه.'), ('اعرض', 'صوّر بضاعتك وضع سعرها.')]),
  s6=('أدوات بين يديك', [('حجوزات منظّمة', 'كل طلب وحالته في مكانه.'), ('توصيل', 'شركات توصيل تستلم منك.'), ('كوبونات', 'اصنع عروضك بنفسك.'), ('محفظة', 'أرباحك وحركاتها أمامك.')]),
  s7=('قبل أن تسأل', [('هل أحتاج محلّاً؟', 'لا. يكفي أن تكون عندك بضاعة.'), ('متى تأخذون نسبة؟', 'عمولة المنصّة تُؤخذ من البيعة حين تتمّ.'), ('من يوصل؟', 'شركات توصيل مرتبطة بالتطبيق.')]),
  s8='مكانك في السوق<br>محجوز.'),
 'm2': dict(
  title='بِع وأنت<br>على الهواء', sub='بثّ مباشر وريلز ومزادات من هاتفك', cta='امسح وابدأ البث',
  s2=('الزبون يشتري ما يراه', 'صورة واحدة لا تكفي. حين يراك الزبون تمسك القطعة وتجيب عن سؤاله، يقرّر أسرع.'),
  s3=('طرق كثيرة لتعرض', ['بثّ مباشر تتكلّم فيه', 'ريلز تبقى بعد البث', 'مزاد لقطعتك المميّزة', 'منتجات بسعر ثابت', 'وكلّها في متجر واحد']),
  s4='هاتفك هو<br>استوديو البيع.',
  s5=('أوّل بثّ لك', [('جهّز', 'اختر البضاعة التي ستعرضها.'), ('ابدأ', 'اضغط بثّ وتكلّم مع زبائنك.'), ('بِع', 'يحجزون القطعة وهم يشاهدون.')]),
  s6=('البث يعمل لك', [('تعليقات مباشرة', 'اسمع زبائنك وجاوبهم.'), ('مشرف معك', 'من يساعدك في إدارة البث.'), ('متابعون', 'يعرفون متى تبثّ.'), ('مزاد في البث', 'ارفع الحماس وبِع القطعة.')]),
  s7=('قبل أن تسأل', [('هل أحتاج كاميرا؟', 'لا، هاتفك يكفي.'), ('هل أحتاج برنامجاً آخر؟', 'لا، البث من داخل التطبيق.'), ('وبعد البث؟', 'تتابع الحجوزات من متجرك.')]),
  s8='أنت على الهواء<br>بعد قليل.'),
 'm3': dict(
  title='وسّع تجارتك<br>بلا محلّ ثانٍ', sub='بيع بالجملة ومندوبون يسوّقون لك', cta='امسح وكبّر تجارتك',
  s2=('بضاعتك عند غيرك أيضاً', 'بدل أن تنتظر الزبون واحداً واحداً، بِع كمّيات لتجّار آخرين، ودع المندوبين يوصلون بضاعتك إلى زبائنهم.'),
  s3=('طريقان للتوسّع', ['جملة: تاجر يطلب كمّية', 'توافق فتنتقل إليه', 'مندوب: يطلب تمثيلك', 'تتّفقان على النسبة', 'وكل شيء مسجّل']),
  s4='بِع أكثر<br>من مكانك.',
  s5=('كيف تبيع بالجملة؟', [('يصلك طلب', 'تاجر يحدّد الكمّية التي يريدها.'), ('توافق', 'تُخصم الكمّية من مخزونك.'), ('تقبض', 'ويصل الثمن إلى محفظتك.')]),
  s6=('ومع المندوبين', [('نسبة متّفق عليها', 'تثبت بعد أن توافق عليها.'), ('أنت من يوافق', 'لا يمثّلك أحد دون قبولك.'), ('حجوزات عبره', 'ترى ما جاء عن طريقه.'), ('محفظة واحدة', 'حركاتك كلّها أمامك.')]),
  s7=('قبل أن تسأل', [('من يحدّد النسبة؟', 'تتّفق عليها مع المندوب وتثبت بعد قبولك.'), ('هل أفقد بضاعتي؟', 'في الجملة تنتقل ملكيّة الكمّية المباعة فقط.'), ('أين أرى أرباحي؟', 'في محفظتك داخل التطبيق.')]),
  s8='تجارتك أكبر<br>من محلّك.'),
}


def uri(path):
    return 'file:///' + path.replace('\\', '/')


def img(name):
    """نسخة JPEG بحجم الطباعة: صور PNG الأصلية تُثقل الـPDF بلا فائدة."""
    dst = os.path.join(OUT, 'img', name + '.jpg')
    if not os.path.exists(dst):
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        src = next(p for p in (os.path.join(HERE, 'img', name + e) for e in ('.jpg', '.png')) if os.path.exists(p))
        im = Image.open(src).convert('RGB')
        w = max(1820, im.width)
        im.resize((w, round(im.height * w / im.width)), Image.LANCZOS).save(dst, quality=90)
    return uri(dst)


def qr(code):
    q = qrcode.QRCode(error_correction=qrcode.constants.ERROR_CORRECT_Q, border=0)
    q.add_data(SITE + code)
    q.make()
    m = q.get_matrix(); n = len(m)
    d = ''.join(f'M{x} {y}h1v1h-1z' for y, r in enumerate(m) for x, v in enumerate(r) if v)
    return f'<svg class="qr" viewBox="-3 -3 {n+6} {n+6}"><rect x="-3" y="-3" width="{n+6}" height="{n+6}" rx="1.6" fill="#fff"/><path d="{d}" fill="#24120a"/></svg>'


# قوس الشعار نفسه (قوس مدبّب) قالباً للصور.
ARCH = 'M0 100V38C0 22 10 17 24 11C36 6 44 4 50 0C56 4 64 6 76 11C90 17 100 22 100 38V100Z'

CSS = '''
@font-face{font-family:Lal;src:url(%(f)s/Lalezar.ttf)}
@font-face{font-family:Taj;font-weight:500;src:url(%(f)s/Tajawal-Medium.ttf)}
@font-face{font-family:Taj;font-weight:800;src:url(%(f)s/Tajawal-ExtraBold.ttf)}
@page{size:154mm 216mm;margin:0}
*{box-sizing:border-box;margin:0;padding:0}
body{font:500 11.6pt/1.65 Taj;color:var(--d);-webkit-print-color-adjust:exact}
.p{position:relative;width:154mm;height:216mm;overflow:hidden;page-break-after:always;background:#fff8ec}
.p:last-child{page-break-after:auto}
.in{position:absolute;inset:17mm 17mm 17mm 17mm;z-index:3}
h1,h2,.big{font-family:Lal;font-weight:400;line-height:1.16}
h2{font-size:33pt;color:var(--d)}
.full{position:absolute;inset:0;width:100%%;height:100%%;object-fit:cover}
.awn{z-index:2;position:absolute;left:0;right:0;top:0;height:22mm;display:block;width:100%%}
.logo{display:flex;align-items:center;gap:3mm;font:400 19pt/1 Lal}
.logo img{width:12mm;height:12mm;border-radius:3mm}
.num{position:absolute;bottom:9mm;left:0;right:0;text-align:center;font:800 9pt Taj;opacity:.6;z-index:4}
.qr{display:block}
.arch{position:absolute}
'''


def awning(a, b, n=14):
    w = 100 / n
    s = ''.join(f'<path d="M{i*w} 0h{w}v9a{w/2} {w/2} 0 0 1 -{w} 0z" fill="{a if i%2 else b}"/>' for i in range(n))
    return f'<svg class="awn" viewBox="0 0 100 13.2" preserveAspectRatio="none">{s}</svg>'


_clip = 0
def arch(src, style, pos='50% 50%'):
    global _clip
    _clip += 1
    i = f'a{_clip}'
    return (f'<div class="arch" style="{style};clip-path:url(#{i})"><img src="{src}" style="width:100%;height:100%;object-fit:cover;object-position:{pos}">'
            f'<svg width="0" height="0" style="position:absolute"><clipPath id="{i}" clipPathUnits="objectBoundingBox"><path transform="scale(.01)" d="{ARCH}"/></clipPath></svg></div>')


def arcade(color, opacity=1):
    """صفّ أقواس الشعار، حاشيةً سفلية."""
    n = 5; w = 100 / n
    s = ''.join(f'<g transform="translate({i*w} 0) scale({w/100} .4)"><path d="M8 100V40C8 24 20 18 30 13C40 8 46 6 50 1C54 6 60 8 70 13C80 18 92 24 92 40V100H78V44C78 30 70 27 62 23C56 20 52 18 50 15C48 18 44 20 38 23C30 27 22 30 22 44V100Z" fill="{color}"/></g>' for i in range(n))
    return f'<svg viewBox="0 0 100 40" preserveAspectRatio="none" style="position:absolute;left:0;right:0;bottom:0;width:100%;height:44mm;opacity:{opacity};z-index:1">{s}</svg>'


def build_html(code):
    b = BOOKS[code]; base, deep, light = THEME[code]
    logo = f'<div class="logo"><img src="{uri(os.path.join(HERE, "..", "assets", "icon", "app_icon.png"))}">الشورجة</div>'
    cover, inner = img(code), img(code + 'b')
    dark_cover = code in ('c2', 'm1')
    pages = []

    # ١ الغلاف: الصورة كاملة، والعنوان أعلاها على تدرّج بلون الكتيّب.
    ink = light if code not in ('c3', 'm3') else deep
    grad = {'c3': '#f9e7c6', 'm3': '#f7b25c', 'c2': '#1a0c05', 'c1': '#b8440c', 'm1': '#4f1a02', 'm2': '#a53c0b'}[code]
    pages.append(f'''<div class="p" style="background:{base}">
      <img class="full" style="top:auto;bottom:0;height:{'150mm' if code in ('c3','m1','m3') else '172mm'};object-position:50% {'75%' if code=='c1' else '100%'}" src="{cover}">
      <div style="position:absolute;inset:0 0 auto 0;height:108mm;background:linear-gradient({grad} 0 58%,{grad}00);z-index:1"></div>
      {awning('#ffecc9','#f28a1c') if code!='m3' else awning('#fff2d9','#c24a10')}
      <div class="in" style="top:29mm;color:{ink};text-align:center">
        <h1 style="font-size:{'44pt' if code in ('c3','m3') else '50pt'};color:{ink}">{b['title']}</h1>
        <p style="font:800 14.5pt/1.4 Taj;margin-top:2.5mm">{b['sub']}</p>
      </div>
      <div style="position:absolute;z-index:4;left:13mm;right:13mm;bottom:13mm;background:#fff8ec;border-radius:7mm;padding:4mm 5mm;display:flex;align-items:center;gap:5mm">
        <div style="width:31mm;flex:none">{qr(code)}</div>
        <div style="flex:1">{logo}<p style="font:800 13.5pt/1.35 Taj;margin-top:2.5mm;color:#b8440c">{b['cta']}</p>
        <p style="font:500 9.5pt Taj;direction:ltr;text-align:right">shorjeh.com/f/{code}</p></div>
      </div></div>''')

    # ٢ الفكرة
    t, p = b['s2']
    pages.append(f'''<div class="p">
      {arch(inner, 'left:27mm;right:27mm;top:17mm;height:108mm')}
      <div class="in" style="top:133mm;text-align:center"><h2>{t}</h2><p style="margin-top:3mm;font-size:13pt">{p}</p></div><div class="num">٢</div></div>''')

    # ٣ القائمة
    t, items = b['s3']
    bg3 = deep if code != 'c3' else '#c24a10'
    rows = ''.join(f'<div style="display:flex;align-items:center;gap:6mm;padding:5.1mm 0;border-bottom:.35mm solid #ffffff40;font:800 17pt/1.3 Taj"><svg width="8mm" height="10mm" viewBox="0 0 100 100" preserveAspectRatio="none" style="flex:none"><path d="{ARCH}" fill="#f28a1c"/></svg>{x}</div>' for x in items)
    pages.append(f'''<div class="p" style="background:{bg3};color:#ffecc9">{arcade('#f28a1c', .16)}
      <div class="in" style="top:26mm"><h2 style="color:#fff;font-size:38pt;margin-bottom:7mm">{t}</h2>{rows}</div><div class="num">٣</div></div>''')

    # ٤ صورة كاملة وجملة
    pages.append(f'''<div class="p"><img class="full" src="{cover}" style="object-position:50% 60%;transform:scale(1.28);transform-origin:{'50% 70%' if code!='c1' else '20% 70%'}">
      <div style="position:absolute;inset:auto 0 0 0;height:120mm;background:linear-gradient(transparent,#1a0c05e6 72%);z-index:1"></div>
      <div class="in big" style="top:auto;bottom:20mm;color:#fff;font-size:41pt;text-align:right">{b['s4']}</div></div>''')

    # ٥ الخطوات: تسلسل فعلي، فالأرقام لها معنى
    t, steps = b['s5']
    rows = ''.join(f'''<div style="display:flex;gap:7mm;align-items:center;margin-bottom:8mm">
       <div style="position:relative;width:25mm;height:33mm;flex:none"><svg viewBox="0 0 100 100" preserveAspectRatio="none" style="position:absolute;inset:0;width:100%;height:100%"><path d="{ARCH}" fill="{'#e4611a'}"/></svg><div style="position:absolute;inset:9mm 0 0 0;text-align:center;font:400 33pt/1 Lal;color:#fff">{n}</div></div>
       <div><div style="font:400 24pt/1.2 Lal;color:{deep}">{h}</div><div style="font-size:13.5pt">{x}</div></div></div>''' for n, (h, x) in zip('١٢٣', steps))
    pages.append(f'''<div class="p" style="background:#ffecc9">{awning('#e4611a','#fff8ec')}
      <div class="in" style="top:36mm"><h2 style="font-size:38pt;margin-bottom:9mm">{t}</h2>{rows}</div><div class="num">٥</div></div>''')

    # ٦ أربع مزايا
    t, feats = b['s6']
    cells = ''.join(f'<div style="border-top:1.2mm solid #e4611a;padding-top:4mm"><div style="font:400 20pt/1.2 Lal;color:{deep}">{h}</div><div style="font-size:12.5pt;line-height:1.55;margin-top:1mm">{x}</div></div>' for h, x in feats)
    pages.append(f'''<div class="p">
      <div class="in" style="top:19mm"><h2 style="font-size:38pt;margin-bottom:6mm">{t}</h2>
      <div style="display:grid;grid-template-columns:1fr 1fr;gap:7mm 9mm">{cells}</div></div>
      {arch(inner, 'left:17mm;right:17mm;bottom:-14mm;height:96mm', '50% 55%')}</div>''')

    # ٧ أسئلة
    t, qs = b['s7']
    rows = ''.join(f'<div style="background:#fff8ec;border-radius:6mm;padding:6mm 7mm;margin-bottom:5.5mm;color:#2b1509"><div style="font:400 19pt/1.3 Lal;color:#b8440c">{q}</div><div style="font-size:13pt">{a}</div></div>' for q, a in qs)
    pages.append(f'''<div class="p" style="background:#e4611a">{arcade('#b8440c', .55)}
      <div class="in" style="top:26mm"><h2 style="color:#fff;font-size:38pt;margin-bottom:8mm">{t}</h2>{rows}</div><div class="num" style="color:#fff">٧</div></div>''')

    # ٨ الغلاف الأخير: الباركود هو البطل
    pages.append(f'''<div class="p" style="background:{'#24120a' if dark_cover else '#e4611a'};color:#ffecc9">{awning('#ffecc9','#f28a1c')}{arcade('#ffecc9', .09)}
      <div class="in" style="top:33mm;text-align:center"><h2 style="color:#fff;font-size:42pt">{b['s8']}</h2>
      <div style="width:72mm;margin:8mm auto 5mm">{qr(code)}</div>
      <p style="font:800 16pt/1.4 Taj">افتح كاميرا هاتفك ووجّهها إلى المربّع</p>
      <p style="font:500 12.5pt Taj;direction:ltr;margin-top:1mm">shorjeh.com/f/{code}</p>
      <div style="display:flex;justify-content:center;margin-top:8mm">{logo}</div></div></div>''')

    style = CSS % {'f': uri(os.path.join(HERE, 'fonts'))}
    return f'<!doctype html><html lang="ar" dir="rtl"><meta charset="utf-8"><title>{code}</title><style>:root{{--d:{deep}}}{style}</style><body>{"".join(pages)}</body></html>'


def chrome(*args):
    subprocess.run([CHROME, '--headless=new', '--disable-gpu', '--hide-scrollbars', '--allow-file-access-from-files',
                    '--virtual-time-budget=8000', f'--user-data-dir={os.path.join(OUT, "_chrome")}', *args],
                   check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=110)


def main(codes):
    os.makedirs(OUT, exist_ok=True)
    for code in codes:
        html = os.path.join(OUT, code + '.html')
        open(html, 'w', encoding='utf8').write(build_html(code))
        chrome('--no-pdf-header-footer', f'--print-to-pdf={os.path.join(OUT, f"shorjeh-{code}-print.pdf")}', uri(html))
        # شريط واحد من الصفحات الثماني ثم قصّه، بعد حذف النزف.
        shot = os.path.join(OUT, code + '.png')
        mm = 96 / 25.4; w, h = 154 * mm, 216 * mm; k = 2
        chrome(f'--window-size={round(w)+1},{int(h*8)+4}', f'--force-device-scale-factor={k}', f'--screenshot={shot}', uri(html))
        im = Image.open(shot).convert('RGB')
        web = os.path.join(BACKEND, 'flipbooks', code); os.makedirs(web, exist_ok=True)
        sheet = Image.new('RGB', (4 * 420, 2 * 596), '#888')
        x_off = im.width - w * k  # الصفحة RTL تُحاذى يميناً
        for n in range(8):
            c = 3 * mm * k
            box = (round(x_off + c), round(n * h * k + c), round(x_off + w * k - c), round((n + 1) * h * k - c))
            pg = im.crop(box)
            pg.resize((1000, 1419), Image.LANCZOS).save(os.path.join(web, f'{n+1}.webp'), quality=80, method=6)
            pg.resize((420, 596), Image.LANCZOS)
            sheet.paste(pg.resize((416, 590), Image.LANCZOS), ((3 - n % 4) * 420 + 2, (n // 4) * 596 + 3))
        sheet.save(os.path.join(OUT, f'{code}-sheet.png'))
        os.remove(shot)
        land = os.path.join(BACKEND, 'img', 'campaigns'); os.makedirs(land, exist_ok=True)
        src = Image.open(os.path.join(OUT, 'img', code + '.jpg'))
        src.resize((900, round(src.height * 900 / src.width)), Image.LANCZOS).save(os.path.join(land, code + '.jpg'), quality=80, optimize=True)
        print('ok', code)


if __name__ == '__main__':
    main(sys.argv[1:] or list(BOOKS))

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/app.dart';
import '../core/fx.dart';
import '../core/data.dart';
import '../shared/messages.dart';
import 'catalog_screen.dart';

/// بيانات واجهة المتجر (النصوص والسوشيال) — في stores/{sid}/meta/storefront
DocumentReference<Map<String, dynamic>> get storefrontRef => storeMeta('storefront');

/// البانرات: كل بانر مستند لوحده عشان الصور متعديش حجم المستند
Query<Map<String, dynamic>> get bannersQuery =>
    db.collection('stores').doc(sid).collection('meta').where('kind', isEqualTo: 'banner');

const String kSolAbout =
    'SOL مش مجرد عطر… SOL حكاية بتبدأ من أول رشة.\n\nبنختار مكوناتنا بعناية من أجود الزيوت العطرية، وبنصمم كل عطر عشان يعيش معاك طول اليوم ويسيب بصمة متتنسيش. عطور فاخرة بأسعار تناسب محلك وتكسّبك.';

const List<Map<String, String>> kSolValues = [
  {'title': 'ثبات عالي', 'text': 'عطور بتعيش معاك طول اليوم'},
  {'title': 'خامات أصلية', 'text': 'زيوت عطرية مختارة بعناية'},
  {'title': 'مكسب مضمون', 'text': 'أسعار جملة وخصومات ونقاط'},
  {'title': 'توصيل لحد المحل', 'text': 'بنزورك ونوصّل طلبك'},
];

/// الصفحة الرئيسية للعميل: بتحكي عن البراند
class HomeTab extends StatelessWidget {
  final void Function(int tab)? onGo;
  final VoidCallback? onChat;
  const HomeTab({super.key, this.onGo, this.onChat});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: storefrontRef.snapshots(),
      builder: (context, sf) {
        final f = sf.data?.data() ?? <String, dynamic>{};
        final isSol = sid == kMainStore;
        final aboutTitle = (f['aboutTitle'] ?? '').toString().isNotEmpty
            ? f['aboutTitle'].toString()
            : 'حكاية $storeName';
        final aboutText = (f['aboutText'] ?? '').toString().isNotEmpty
            ? f['aboutText'].toString()
            : (isSol ? kSolAbout : (Session.store['welcome'] ?? '').toString());
        final values = (f['values'] as List?)
                ?.map((e) => Map<String, String>.from(
                    (e as Map).map((k, v) => MapEntry('$k', '$v'))))
                .toList() ??
            (isSol ? kSolValues : <Map<String, String>>[]);
        final social = Map<String, dynamic>.from(f['social'] ?? {});
        return ListView(padding: const EdgeInsets.only(bottom: 90), children: [
          _Hero(f: f),
          const AnnouncementsStrip(),
          if (aboutText.isNotEmpty)
            _AboutCard(title: aboutTitle, text: aboutText, image: f['aboutImage']),
          if (values.isNotEmpty) _Values(values: values),
          if (f['showFeatured'] != false) _Featured(onAll: () => onGo?.call(1)),
          if (f['showOffers'] != false) _OffersStrip(onAll: () => onGo?.call(2)),
          _Contact(social: social, onChat: onChat),
          const SizedBox(height: 10),
          Center(
            child: Text('$storeName${storeSlogan.isEmpty ? '' : ' — $storeSlogan'}',
                style: const TextStyle(color: Colors.black45)),
          ),
        ]);
      },
    );
  }
}

class _Hero extends StatefulWidget {
  final Map<String, dynamic> f;
  const _Hero({required this.f});
  @override
  State<_Hero> createState() => _HeroState();
}

class _HeroState extends State<_Hero> {
  final page = PageController();
  int index = 0;
  Timer? timer;
  int count = 0;

  @override
  void initState() {
    super.initState();
    timer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted || count < 2 || !page.hasClients) return;
      page.animateToPage((index + 1) % count,
          duration: const Duration(milliseconds: 500), curve: Curves.easeInOut);
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    page.dispose();
    super.dispose();
  }

  Widget _brandHero() => Container(
        height: 230,
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF0A0A0A), Color(0xFF2A2418)],
          ),
        ),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const StoreLogo(size: 110, radius: 16),
          const SizedBox(height: 12),
          Text(
              (widget.f['heroTitle'] ?? '').toString().isNotEmpty
                  ? widget.f['heroTitle'].toString()
                  : storeName,
              style: const TextStyle(color: kAccent, fontSize: 22, fontWeight: FontWeight.bold)),
          if (storeSlogan.isNotEmpty || (widget.f['heroSubtitle'] ?? '').toString().isNotEmpty)
            Text(
                (widget.f['heroSubtitle'] ?? '').toString().isNotEmpty
                    ? widget.f['heroSubtitle'].toString()
                    : storeSlogan,
                style: const TextStyle(color: Colors.white70)),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: bannersQuery.snapshots(),
      builder: (context, snap) {
        final docs = [...(snap.data?.docs ?? <QueryDocumentSnapshot<Map<String, dynamic>>>[])]
          ..sort((a, b) => toI(a.data()['order']).compareTo(toI(b.data()['order'])));
        count = docs.length;
        if (docs.isEmpty) return _brandHero();
        return SizedBox(
          height: 230,
          child: Stack(children: [
            PageView.builder(
              controller: page,
              itemCount: docs.length,
              onPageChanged: (i) => setState(() => index = i),
              itemBuilder: (c, i) {
                final b = docs[i].data();
                return Stack(fit: StackFit.expand, children: [
                  B64Image(b['image']),
                  Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Color(0xCC000000)],
                      ),
                    ),
                  ),
                  Positioned(
                    right: 16,
                    left: 16,
                    bottom: 26,
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      if ((b['title'] ?? '').toString().isNotEmpty)
                        Text(b['title'],
                            style: const TextStyle(
                                color: kAccent, fontSize: 22, fontWeight: FontWeight.bold)),
                      if ((b['subtitle'] ?? '').toString().isNotEmpty)
                        Text(b['subtitle'],
                            style: const TextStyle(color: Colors.white, fontSize: 15)),
                    ]),
                  ),
                ]);
              },
            ),
            if (docs.length > 1)
              Positioned(
                bottom: 8,
                left: 0,
                right: 0,
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  for (var i = 0; i < docs.length; i++)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      width: i == index ? 18 : 7,
                      height: 7,
                      decoration: BoxDecoration(
                          color: i == index ? kAccent : Colors.white54,
                          borderRadius: BorderRadius.circular(4)),
                    ),
                ]),
              ),
          ]),
        );
      },
    );
  }
}

class _AboutCard extends StatelessWidget {
  final String title, text;
  final dynamic image;
  const _AboutCard({required this.title, required this.text, this.image});
  @override
  Widget build(BuildContext context) {
    final hasImage = (image ?? '').toString().isNotEmpty;
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 14, 12, 6),
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (hasImage) AspectRatio(aspectRatio: 16 / 9, child: B64Image(image)),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(width: 4, height: 22, color: kAccent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(title,
                    style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
              ),
            ]),
            const SizedBox(height: 10),
            Text(text, style: const TextStyle(fontSize: 15, height: 1.8, color: Colors.black87)),
          ]),
        ),
      ]),
    );
  }
}

class _Values extends StatelessWidget {
  final List<Map<String, String>> values;
  const _Values({required this.values});
  @override
  Widget build(BuildContext context) {
    const icons = [Icons.auto_awesome, Icons.spa, Icons.trending_up, Icons.local_shipping,
      Icons.verified, Icons.favorite];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        childAspectRatio: 1.9,
        children: [
          for (var i = 0; i < values.length; i++)
            Card(
              margin: const EdgeInsets.all(4),
              color: kPrimary,
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Row(children: [
                  Icon3D(icons[i % icons.length],
                      size: 40, tone: tGold, float: true, delayMs: 120 * i),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(values[i]['title'] ?? '',
                            style: const TextStyle(
                                color: kAccent, fontWeight: FontWeight.bold, fontSize: 14)),
                        if ((values[i]['text'] ?? '').isNotEmpty)
                          Text(values[i]['text']!,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Colors.white70, fontSize: 11)),
                      ],
                    ),
                  ),
                ]),
              ),
            ),
        ],
      ),
    );
  }
}

class _Featured extends StatelessWidget {
  final VoidCallback onAll;
  const _Featured({required this.onAll});
  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: scoped('products').where('active', isEqualTo: true).snapshots(),
      builder: (context, snap) {
        final all = snap.data?.docs ?? <QueryDocumentSnapshot<Map<String, dynamic>>>[];
        var list = all.where((d) => d.data()['featured'] == true).toList();
        if (list.isEmpty) list = sortByDate(all).take(8).toList();
        if (list.isEmpty) return const SizedBox();
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SectionTitle('✨ مختارات $storeName',
              trailing: TextButton(onPressed: onAll, child: const Text('كل المنتجات'))),
          SizedBox(
            height: 290,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              itemCount: list.length,
              itemBuilder: (c, i) => SizedBox(
                width: 175,
                child: ProductCard(list[i].id, list[i].data()),
              ),
            ),
          ),
        ]);
      },
    );
  }
}

class _OffersStrip extends StatelessWidget {
  final VoidCallback onAll;
  const _OffersStrip({required this.onAll});
  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: scoped('offers').where('active', isEqualTo: true).snapshots(),
      builder: (context, snap) {
        final now = DateTime.now();
        final list = (snap.data?.docs ?? <QueryDocumentSnapshot<Map<String, dynamic>>>[])
            .where((d) {
          final e = tsToDate(d.data()['endsAt']);
          return e == null || e.isAfter(now);
        }).toList();
        if (list.isEmpty) return const SizedBox();
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SectionTitle('🔥 عروض دلوقتي',
              trailing: TextButton(onPressed: onAll, child: const Text('كل العروض'))),
          SizedBox(
            height: 120,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              itemCount: list.length,
              itemBuilder: (c, i) {
                final o = list[i].data();
                final disc = toD(o['discount']);
                return GestureDetector(
                  onTap: onAll,
                  child: Container(
                    width: 250,
                    margin: const EdgeInsets.all(4),
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                        color: kPrimary, borderRadius: BorderRadius.circular(14)),
                    child: Row(children: [
                      if ((o['image'] ?? '').toString().isNotEmpty)
                        SizedBox(width: 90, height: double.infinity, child: B64Image(o['image'])),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.all(10),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text((o['title'] ?? '').toString(),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      color: Colors.white, fontWeight: FontWeight.bold)),
                              if (disc > 0)
                                Text('خصم ${disc.toStringAsFixed(disc % 1 == 0 ? 0 : 1)}%',
                                    style: const TextStyle(
                                        color: kAccent, fontSize: 18, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                      ),
                    ]),
                  ),
                );
              },
            ),
          ),
        ]);
      },
    );
  }
}

class _Contact extends StatelessWidget {
  final Map<String, dynamic> social;
  final VoidCallback? onChat;
  const _Contact({required this.social, this.onChat});

  Future<void> _open(String url) =>
      launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);

  @override
  Widget build(BuildContext context) {
    final phone = (social['phone'] ?? Session.store['phone'] ?? '').toString();
    final wa = (social['whatsapp'] ?? phone).toString();
    String waLink(String p) {
      var d = p.replaceAll(RegExp(r'[^0-9]'), '');
      if (d.startsWith('0')) d = '2$d';
      return 'https://wa.me/$d';
    }

    final buttons = <Widget>[
      if (onChat != null)
        _btn(Icons.chat_bubble, 'كلّمنا', onChat!),
      if (wa.isNotEmpty) _btn(Icons.message, 'واتساب', () => _open(waLink(wa))),
      if (phone.isNotEmpty) _btn(Icons.call, 'اتصال', () => _open('tel:$phone')),
      if ((social['facebook'] ?? '').toString().isNotEmpty)
        _btn(Icons.facebook, 'فيسبوك', () => _open(social['facebook'])),
      if ((social['instagram'] ?? '').toString().isNotEmpty)
        _btn(Icons.camera_alt, 'إنستجرام', () => _open(social['instagram'])),
      if ((social['tiktok'] ?? '').toString().isNotEmpty)
        _btn(Icons.music_note, 'تيك توك', () => _open(social['tiktok'])),
      if ((social['website'] ?? '').toString().isNotEmpty)
        _btn(Icons.language, 'الموقع', () => _open(social['website'])),
    ];
    if (buttons.isEmpty) return const SizedBox();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SectionTitle('📞 تواصل معانا'),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Wrap(spacing: 8, runSpacing: 8, children: buttons),
      ),
    ]);
  }

  Widget _btn(IconData i, String t, VoidCallback onTap) => ActionChip(
        avatar: Icon(i, size: 18, color: kAccent),
        label: Text(t),
        backgroundColor: kPrimary,
        labelStyle: const TextStyle(color: Colors.white),
        onPressed: onTap,
      );
}

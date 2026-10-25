import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../core/app.dart';
import '../customer/home_tab.dart';

/// صاحب المحل بيتحكم في الصفحة الرئيسية اللي العملاء بيشوفوها
class StorefrontEditor extends StatefulWidget {
  const StorefrontEditor({super.key});
  @override
  State<StorefrontEditor> createState() => _StorefrontEditorState();
}

class _StorefrontEditorState extends State<StorefrontEditor> {
  final heroTitle = TextEditingController();
  final heroSubtitle = TextEditingController();
  final aboutTitle = TextEditingController();
  final aboutText = TextEditingController();
  final social = <String, TextEditingController>{
    'whatsapp': TextEditingController(),
    'phone': TextEditingController(),
    'facebook': TextEditingController(),
    'instagram': TextEditingController(),
    'tiktok': TextEditingController(),
    'website': TextEditingController(),
  };
  String? aboutImage;
  List<Map<String, String>> values = [];
  bool showFeatured = true, showOffers = true;
  bool loaded = false, busy = false;

  @override
  void initState() {
    super.initState();
    storefrontRef.get().then((s) {
      final f = s.data() ?? {};
      if (!mounted) return;
      setState(() {
        heroTitle.text = (f['heroTitle'] ?? '').toString();
        heroSubtitle.text = (f['heroSubtitle'] ?? '').toString();
        aboutTitle.text = (f['aboutTitle'] ?? '').toString();
        aboutText.text = (f['aboutText'] ?? (sid == kMainStore ? kSolAbout : '')).toString();
        aboutImage = (f['aboutImage'] ?? '').toString();
        final so = Map<String, dynamic>.from(f['social'] ?? {});
        social.forEach((k, c) => c.text = (so[k] ?? '').toString());
        values = (f['values'] as List?)
                ?.map((e) => Map<String, String>.from(
                    (e as Map).map((k, v) => MapEntry('$k', '$v'))))
                .toList() ??
            (sid == kMainStore ? [...kSolValues] : []);
        showFeatured = f['showFeatured'] != false;
        showOffers = f['showOffers'] != false;
        loaded = true;
      });
    });
  }

  Future<void> save() async {
    setState(() => busy = true);
    try {
      await storefrontRef.set({
        'heroTitle': heroTitle.text.trim(),
        'heroSubtitle': heroSubtitle.text.trim(),
        'aboutTitle': aboutTitle.text.trim(),
        'aboutText': aboutText.text.trim(),
        'aboutImage': aboutImage ?? '',
        'values': values,
        'social': {for (final e in social.entries) e.key: e.value.text.trim()},
        'showFeatured': showFeatured,
        'showOffers': showOffers,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      if (mounted) toast(context, 'اتحفظت واجهة المتجر ✔');
    } catch (e) {
      if (mounted) toast(context, '$e', error: true);
    }
    if (mounted) setState(() => busy = false);
  }

  Future<void> editValue([int? i]) async {
    final t = TextEditingController(text: i == null ? '' : values[i]['title']);
    final d = TextEditingController(text: i == null ? '' : values[i]['text']);
    final r = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('ميزة'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: t, decoration: const InputDecoration(labelText: 'العنوان (زي: ثبات عالي)')),
          const SizedBox(height: 8),
          TextField(controller: d, decoration: const InputDecoration(labelText: 'وصف قصير')),
        ]),
        actions: [
          if (i != null)
            TextButton(
                style: TextButton.styleFrom(foregroundColor: kDanger),
                onPressed: () => Navigator.pop(c, 'delete'),
                child: const Text('حذف')),
          FilledButton(onPressed: () => Navigator.pop(c, 'save'), child: const Text('تمام')),
        ],
      ),
    );
    if (r == null) return;
    setState(() {
      if (r == 'delete') {
        values.removeAt(i!);
      } else if (t.text.trim().isNotEmpty) {
        final v = {'title': t.text.trim(), 'text': d.text.trim()};
        if (i == null) {
          values.add(v);
        } else {
          values[i] = v;
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('واجهة المتجر'),
        actions: [
          TextButton.icon(
            onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => Scaffold(
                        appBar: AppBar(title: const Text('معاينة — زي ما العميل بيشوفها')),
                        body: const HomeTab()))),
            icon: const Icon(Icons.visibility, color: kAccent),
            label: const Text('معاينة', style: TextStyle(color: kAccent)),
          ),
        ],
      ),
      body: !loaded
          ? const Loading()
          : ListView(padding: const EdgeInsets.only(bottom: 100), children: [
              const SectionTitle('🖼️ البانرات (صور متحركة فوق الصفحة)'),
              const _BannersEditor(),
              const SectionTitle('العنوان الرئيسي (لو مفيش بانرات)'),
              _f(heroTitle, 'العنوان (فاضي = اسم المحل)'),
              _f(heroSubtitle, 'تحت العنوان (فاضي = جملة المحل)'),
              const SectionTitle('📖 حكاية البراند'),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: GestureDetector(
                  onTap: () async {
                    final p = await pickImageB64(context, maxWidth: 900);
                    if (p != null) setState(() => aboutImage = p);
                  },
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: SizedBox(
                      height: 150,
                      child: Stack(fit: StackFit.expand, children: [
                        B64Image(aboutImage, placeholder: Icons.add_photo_alternate_outlined),
                        Positioned(
                          bottom: 6,
                          left: 6,
                          child: Row(children: [
                            const Chip(label: Text('صورة البراند')),
                            if ((aboutImage ?? '').isNotEmpty) ...[
                              const SizedBox(width: 4),
                              ActionChip(
                                  label: const Text('شيلها'),
                                  onPressed: () => setState(() => aboutImage = '')),
                            ],
                          ]),
                        ),
                      ]),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              _f(aboutTitle, 'العنوان (فاضي = حكاية $storeName)'),
              _f(aboutText, 'احكي عن البراند', lines: 6),
              SectionTitle('⭐ مميزاتنا (${values.length})',
                  trailing: TextButton.icon(
                      onPressed: () => editValue(),
                      icon: const Icon(Icons.add),
                      label: const Text('إضافة'))),
              for (var i = 0; i < values.length; i++)
                Card(
                  child: ListTile(
                    onTap: () => editValue(i),
                    leading: const Icon(Icons.auto_awesome, color: kAccent),
                    title: Text(values[i]['title'] ?? ''),
                    subtitle: Text(values[i]['text'] ?? ''),
                    trailing: const Icon(Icons.edit, size: 18),
                  ),
                ),
              const SectionTitle('🛍️ الأقسام اللي تظهر'),
              SwitchListTile(
                value: showFeatured,
                onChanged: (v) => setState(() => showFeatured = v),
                title: const Text('مختارات المنتجات'),
                subtitle: const Text('علّم على "صنف مميز" من صفحة أي صنف عشان يظهر هنا'),
              ),
              SwitchListTile(
                value: showOffers,
                onChanged: (v) => setState(() => showOffers = v),
                title: const Text('العروض'),
              ),
              const SectionTitle('📞 التواصل والسوشيال'),
              _f(social['whatsapp']!, 'رقم الواتساب', ltr: true),
              _f(social['phone']!, 'رقم الاتصال', ltr: true),
              _f(social['facebook']!, 'لينك فيسبوك', ltr: true),
              _f(social['instagram']!, 'لينك إنستجرام', ltr: true),
              _f(social['tiktok']!, 'لينك تيك توك', ltr: true),
              _f(social['website']!, 'لينك الموقع', ltr: true),
            ]),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: SizedBox(
            height: 48,
            child: FilledButton.icon(
              onPressed: busy || !loaded ? null : save,
              icon: const Icon(Icons.save),
              label: const Text('حفظ الواجهة'),
            ),
          ),
        ),
      ),
    );
  }

  Widget _f(TextEditingController c, String label, {int lines = 1, bool ltr = false}) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: TextField(
          controller: c,
          maxLines: lines,
          textDirection: ltr ? TextDirection.ltr : null,
          decoration: InputDecoration(labelText: label),
        ),
      );
}

class _BannersEditor extends StatelessWidget {
  const _BannersEditor();

  CollectionReference<Map<String, dynamic>> get _col =>
      db.collection('stores').doc(sid).collection('meta');

  Future<void> _edit(BuildContext context, {String? id, Map<String, dynamic>? b, int order = 0}) async {
    String? image = b?['image'];
    final title = TextEditingController(text: b?['title'] ?? '');
    final sub = TextEditingController(text: b?['subtitle'] ?? '');
    final r = await showDialog<String>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: Text(id == null ? 'بانر جديد' : 'تعديل البانر'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              GestureDetector(
                onTap: () async {
                  final p = await pickImageB64(context, maxWidth: 1000);
                  if (p != null) set(() => image = p);
                },
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: SizedBox(
                      height: 130,
                      width: double.infinity,
                      child: B64Image(image, placeholder: Icons.add_photo_alternate_outlined)),
                ),
              ),
              const SizedBox(height: 6),
              const Text('دوس على الصورة عشان تختار', style: TextStyle(fontSize: 12)),
              const SizedBox(height: 8),
              TextField(controller: title, decoration: const InputDecoration(labelText: 'عنوان (اختياري)')),
              const SizedBox(height: 8),
              TextField(controller: sub, decoration: const InputDecoration(labelText: 'جملة صغيرة (اختياري)')),
            ]),
          ),
          actions: [
            if (id != null)
              TextButton(
                  style: TextButton.styleFrom(foregroundColor: kDanger),
                  onPressed: () => Navigator.pop(c, 'delete'),
                  child: const Text('حذف')),
            FilledButton(onPressed: () => Navigator.pop(c, 'save'), child: const Text('حفظ')),
          ],
        ),
      ),
    );
    if (r == 'delete' && id != null) {
      await _col.doc(id).delete();
    } else if (r == 'save') {
      if ((image ?? '').isEmpty) {
        if (context.mounted) toast(context, 'اختار صورة للبانر', error: true);
        return;
      }
      final data = {
        'kind': 'banner',
        'image': image,
        'title': title.text.trim(),
        'subtitle': sub.text.trim(),
        'order': b?['order'] ?? order,
      };
      if (id == null) {
        await _col.add(data);
      } else {
        await _col.doc(id).set(data);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: bannersQuery.snapshots(),
      builder: (context, snap) {
        final docs = [...(snap.data?.docs ?? <QueryDocumentSnapshot<Map<String, dynamic>>>[])]
          ..sort((a, b) => toI(a.data()['order']).compareTo(toI(b.data()['order'])));
        return SizedBox(
          height: 120,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            children: [
              for (final d in docs)
                GestureDetector(
                  onTap: () => _edit(context, id: d.id, b: d.data()),
                  child: Container(
                    width: 190,
                    margin: const EdgeInsets.only(left: 8),
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(borderRadius: BorderRadius.circular(10)),
                    child: Stack(fit: StackFit.expand, children: [
                      B64Image(d.data()['image']),
                      if ((d.data()['title'] ?? '').toString().isNotEmpty)
                        Positioned(
                          bottom: 0,
                          left: 0,
                          right: 0,
                          child: Container(
                            color: Colors.black54,
                            padding: const EdgeInsets.all(4),
                            child: Text(d.data()['title'],
                                maxLines: 1,
                                style: const TextStyle(color: Colors.white, fontSize: 12)),
                          ),
                        ),
                    ]),
                  ),
                ),
              GestureDetector(
                onTap: () => _edit(context, order: docs.length),
                child: Container(
                  width: 120,
                  decoration: BoxDecoration(
                    border: Border.all(color: kAccent, width: 1.5),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(Icons.add_photo_alternate, color: kAccent, size: 32),
                    Text('بانر جديد'),
                  ]),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

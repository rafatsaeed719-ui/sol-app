import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../admin/contacts_screen.dart' show openWhatsApp;
import '../core/app.dart';
import '../core/data.dart';
import '../core/fx.dart';

// ======================== رسالة خاصة لعميل ========================

/// المدير يكتب رسالة لعميل واحد: بتظهرله أول ما يفتح التطبيق + إشعار + (اختياري) واتساب
Future<void> sendPersonalMessage(
    BuildContext context, String customerId, Map<String, dynamic> m) async {
  final old = m['personalMessage'] is Map ? Map<String, dynamic>.from(m['personalMessage']) : {};
  final title = TextEditingController(
      text: (old['title'] ?? 'رسالة من $storeName 💌').toString());
  final text = TextEditingController(text: (old['text'] ?? '').toString());
  var alsoWa = false;
  final phone = (m['phone'] ?? '').toString();
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, set) => AlertDialog(
        title: Text('رسالة لـ ${m['shopName'] ?? m['ownerName'] ?? 'العميل'}'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: title, decoration: const InputDecoration(labelText: 'العنوان')),
            const SizedBox(height: 8),
            TextField(
              controller: text,
              maxLines: 5,
              autofocus: true,
              decoration: const InputDecoration(
                  labelText: 'الرسالة',
                  hintText: 'هتظهرله أول ما يفتح التطبيق وكمان كإشعار'),
            ),
            if (phone.isNotEmpty)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: alsoWa,
                onChanged: (v) => set(() => alsoWa = v ?? false),
                title: const Text('ابعتها واتساب كمان'),
              ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('ابعت')),
        ],
      ),
    ),
  );
  if (ok != true || text.text.trim().isEmpty) return;
  try {
    await db.collection('users').doc(customerId).update({
      'personalMessage': {
        'title': title.text.trim(),
        'text': text.text.trim(),
        'at': Timestamp.now(),
      },
    });
    await notify(customerId, title.text.trim(), text.text.trim(), type: 'message');
    if (alsoWa) await openWhatsApp(phone, '${title.text.trim()}\n\n${text.text.trim()}');
    if (context.mounted) toast(context, 'اتبعتت الرسالة ✔');
  } catch (e) {
    if (context.mounted) toast(context, '$e', error: true);
  }
}

/// نافذة شيك فيها رسالة أو إعلان
Future<void> showFancyMessage(BuildContext context,
    {required String title, required String text, String? image, IconData icon = Icons.mark_chat_unread}) {
  return showDialog(
    context: context,
    builder: (c) => Dialog(
      backgroundColor: kPrimary,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: kAccent, width: 1.2)),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if ((image ?? '').isNotEmpty)
            AspectRatio(aspectRatio: 16 / 10, child: B64Image(image))
          else
            Padding(
              padding: const EdgeInsets.only(top: 24),
              child: Icon3D(icon, size: 70, tone: tGold, float: true),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
            child: Column(children: [
              Text(title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: kAccent, fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Text(text,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 16, height: 1.6)),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                height: 46,
                child: FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: kAccent, foregroundColor: kPrimary),
                  onPressed: () => Navigator.pop(c),
                  child: const Text('تمام', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ]),
          ),
        ]),
      ),
    ),
  );
}

// ======================== الإعلانات ========================

CollectionReference<Map<String, dynamic>> get _meta =>
    db.collection('stores').doc(sid).collection('meta');

Query<Map<String, dynamic>> get announcementsQuery =>
    _meta.where('kind', isEqualTo: 'announcement');

/// عند فتح العميل للتطبيق: يعرض الرسالة الخاصة الجديدة، وبعدها آخر إعلان ماشافوش
Future<void> showPendingMessages(BuildContext context, Map<String, dynamic> me) async {
  // ١) الرسالة الخاصة
  final pm = me['personalMessage'];
  if (pm is Map) {
    final at = tsToDate(pm['at']);
    final seen = tsToDate(me['personalMessageSeenAt']);
    if (at != null && (seen == null || seen.isBefore(at))) {
      await showFancyMessage(context,
          title: (pm['title'] ?? 'رسالة من $storeName').toString(),
          text: (pm['text'] ?? '').toString());
      try {
        await db.collection('users').doc(uid).update({'personalMessageSeenAt': Timestamp.now()});
      } catch (_) {}
    }
  }
  if (!context.mounted) return;
  // ٢) الإعلانات اللي ماشافهاش
  try {
    final prefs = await SharedPreferences.getInstance();
    final key = 'seenAnn_${uid}_$sid';
    final seenIds = prefs.getStringList(key) ?? [];
    final snap = await announcementsQuery.get();
    final docs = sortByDate(snap.docs)
        .where((d) => d.data()['active'] != false && d.data()['popup'] != false && !seenIds.contains(d.id))
        .toList();
    // آخر إعلان بس عشان منزعجش العميل
    if (docs.isNotEmpty && context.mounted) {
      final a = docs.first.data();
      await showFancyMessage(context,
          title: (a['title'] ?? '').toString(),
          text: (a['body'] ?? '').toString(),
          image: a['image'],
          icon: Icons.campaign);
    }
    await prefs.setStringList(key, [...seenIds, ...docs.map((d) => d.id)]);
  } catch (_) {}
}

/// كروت الإعلانات في الصفحة الرئيسية
class AnnouncementsStrip extends StatelessWidget {
  const AnnouncementsStrip({super.key});
  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: announcementsQuery.snapshots(),
      builder: (context, s) {
        final docs = sortByDate(s.data?.docs ?? <QueryDocumentSnapshot<Map<String, dynamic>>>[])
            .where((d) => d.data()['active'] != false)
            .take(3)
            .toList();
        if (docs.isEmpty) return const SizedBox();
        return Column(children: [
          for (final d in docs)
            Card(
              margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
              color: const Color(0xFFFFF6E6),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => showFancyMessage(context,
                    title: (d.data()['title'] ?? '').toString(),
                    text: (d.data()['body'] ?? '').toString(),
                    image: d.data()['image'],
                    icon: Icons.campaign),
                child: Row(children: [
                  if ((d.data()['image'] ?? '').toString().isNotEmpty)
                    SizedBox(width: 90, height: 80, child: B64Image(d.data()['image']))
                  else
                    const Padding(
                      padding: EdgeInsets.all(12),
                      child: Icon3D(Icons.campaign, size: 46, tone: tGold),
                    ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text((d.data()['title'] ?? '').toString(),
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                        Text((d.data()['body'] ?? '').toString(),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.black54)),
                      ]),
                    ),
                  ),
                ]),
              ),
            ),
        ]);
      },
    );
  }
}

/// المدير: الإعلانات والرسائل لكل العملاء
class AnnouncementsScreen extends StatelessWidget {
  const AnnouncementsScreen({super.key});

  Future<void> _edit(BuildContext context, {String? id, Map<String, dynamic>? a}) async {
    final title = TextEditingController(text: a?['title'] ?? '');
    final body = TextEditingController(text: a?['body'] ?? '');
    String? image = a?['image'];
    var popup = a?['popup'] != false;
    var alsoNotify = id == null;
    final r = await showDialog<String>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: Text(id == null ? 'إعلان / رسالة لكل العملاء' : 'تعديل الإعلان'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              GestureDetector(
                onTap: () async {
                  final p = await pickImageB64(context, maxWidth: 900);
                  if (p != null) set(() => image = p);
                },
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: SizedBox(
                      height: 120,
                      width: double.infinity,
                      child: B64Image(image, placeholder: Icons.add_photo_alternate_outlined)),
                ),
              ),
              const Text('صورة (اختياري)', style: TextStyle(fontSize: 12)),
              const SizedBox(height: 8),
              TextField(controller: title, decoration: const InputDecoration(labelText: 'العنوان *')),
              const SizedBox(height: 8),
              TextField(
                  controller: body,
                  maxLines: 4,
                  decoration: const InputDecoration(labelText: 'الكلام')),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: popup,
                onChanged: (v) => set(() => popup = v),
                title: const Text('يظهرله أول ما يفتح التطبيق'),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: alsoNotify,
                onChanged: (v) => set(() => alsoNotify = v ?? false),
                title: const Text('ابعت إشعار لكل العملاء'),
              ),
            ]),
          ),
          actions: [
            if (id != null)
              TextButton(
                  style: TextButton.styleFrom(foregroundColor: kDanger),
                  onPressed: () => Navigator.pop(c, 'delete'),
                  child: const Text('حذف')),
            FilledButton(onPressed: () => Navigator.pop(c, 'save'), child: const Text('نشر')),
          ],
        ),
      ),
    );
    if (r == 'delete' && id != null) {
      await _meta.doc(id).delete();
      return;
    }
    if (r != 'save' || title.text.trim().isEmpty) return;
    final data = {
      'kind': 'announcement',
      'title': title.text.trim(),
      'body': body.text.trim(),
      'image': image ?? '',
      'popup': popup,
      'active': true,
      'createdAt': a?['createdAt'] ?? FieldValue.serverTimestamp(),
    };
    if (id == null) {
      await _meta.add(data);
    } else {
      await _meta.doc(id).set(data);
    }
    if (alsoNotify) {
      await notify('all', '📢 ${title.text.trim()}', body.text.trim(), type: 'announcement');
    }
    if (context.mounted) toast(context, 'اتنشر ✔');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('الإعلانات والرسائل')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(context),
        icon: const Icon(Icons.campaign),
        label: const Text('إعلان جديد'),
      ),
      body: StreamBuilder(
        stream: announcementsQuery.snapshots(),
        builder: (context, s) {
          if (s.hasError) return EmptyView('${s.error}');
          if (!s.hasData) return const Loading();
          final docs = sortByDate(s.data!.docs);
          return ListView(padding: const EdgeInsets.only(bottom: 90), children: [
            const Card(
              color: Color(0xFFFFF6E6),
              child: Padding(
                padding: EdgeInsets.all(12),
                child: Text(
                    'الإعلان بيوصل لكل عملاء المحل: إشعار على الموبايل، ونافذة تظهرلهم أول ما يفتحوا التطبيق، وكارت في الصفحة الرئيسية.\n'
                    'ولرسالة لعميل واحد: افتح صفحته ودوس ⋮ ← رسالة خاصة.',
                    style: TextStyle(height: 1.6)),
              ),
            ),
            if (docs.isEmpty) const EmptyView('لسه مفيش إعلانات', icon: Icons.campaign),
            for (var i = 0; i < docs.length; i++)
              FadeSlideIn(
                delayMs: i < 10 ? 40 * i : 0,
                child: Card(
                  child: ListTile(
                    onTap: () => _edit(context, id: docs[i].id, a: docs[i].data()),
                    leading: (docs[i].data()['image'] ?? '').toString().isNotEmpty
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: B64Image(docs[i].data()['image'], width: 54, height: 54))
                        : Icon3D(Icons.campaign, size: 46, tone: [tGold, tBlue, tGreen, tPurple][i % 4]),
                    title: Text((docs[i].data()['title'] ?? '').toString(),
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: docs[i].data()['active'] == false ? Colors.grey : null)),
                    subtitle: Text(
                        '${docs[i].data()['body'] ?? ''}\n${fmtDate(docs[i].data()['createdAt'], time: true)}',
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis),
                    isThreeLine: true,
                    trailing: Switch(
                      value: docs[i].data()['active'] != false,
                      onChanged: (v) => _meta.doc(docs[i].id).update({'active': v}),
                    ),
                  ),
                ),
              ),
          ]);
        },
      ),
    );
  }
}

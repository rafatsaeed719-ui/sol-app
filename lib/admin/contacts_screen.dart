import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/app.dart';
import '../core/fx.dart';

/// رقم مصري بصيغة واتساب الدولية: 01012345678 → 201012345678
String waNumber(String phone) {
  var d = phone.replaceAll(RegExp(r'[^0-9]'), '');
  if (d.startsWith('00')) d = d.substring(2);
  if (d.startsWith('0')) d = '2$d';
  if (d.length == 10 && d.startsWith('1')) d = '20$d';
  return d;
}

Future<void> openWhatsApp(String phone, [String text = '']) => launchUrl(
    Uri.parse('https://wa.me/${waNumber(phone)}${text.isEmpty ? '' : '?text=${Uri.encodeComponent(text)}'}'),
    mode: LaunchMode.externalApplication);

Future<void> callNumber(String phone) =>
    launchUrl(Uri.parse('tel:$phone'), mode: LaunchMode.externalApplication);

/// جهة اتصال واحدة (من الدفتر أو من عملاء التطبيق)
class Recipient {
  final String name, phone, group;
  const Recipient(this.name, this.phone, [this.group = '']);
}

// ======================== دفتر العملاء ========================

class ContactsTab extends StatefulWidget {
  const ContactsTab({super.key});
  @override
  State<ContactsTab> createState() => _ContactsTabState();
}

class _ContactsTabState extends State<ContactsTab> {
  String q = '';
  String group = '';

  Future<void> exportVcf(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) async {
    final b = StringBuffer();
    for (final d in docs) {
      final m = d.data();
      final name = (m['name'] ?? '').toString().replaceAll('\n', ' ');
      b
        ..writeln('BEGIN:VCARD')
        ..writeln('VERSION:3.0')
        ..writeln('FN:$name')
        ..writeln('N:$name;;;;')
        ..writeln('TEL;TYPE=CELL:+${waNumber((m['phone'] ?? '').toString())}');
      if ((m['address'] ?? '').toString().isNotEmpty) {
        b.writeln('ADR;TYPE=WORK:;;${m['address'].toString().replaceAll('\n', ' ')};;;;');
      }
      if ((m['group'] ?? '').toString().isNotEmpty) b.writeln('ORG:${m['group']}');
      b.writeln('END:VCARD');
    }
    final bytes = utf8.encode(b.toString());
    await Share.shareXFiles(
        [XFile.fromData(bytes, name: '$storeName-contacts.vcf', mimeType: 'text/vcard')],
        text: 'أرقام عملاء $storeName');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'addContact',
        onPressed: () =>
            Navigator.push(context, MaterialPageRoute(builder: (_) => const ContactForm())),
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('عميل جديد'),
      ),
      body: StreamBuilder(
        stream: scoped('contacts').snapshots(),
        builder: (context, snap) {
          if (snap.hasError) return EmptyView('${snap.error}');
          if (!snap.hasData) return const Loading();
          final all = [...snap.data!.docs]..sort((a, b) =>
              (a.data()['name'] ?? '').toString().compareTo((b.data()['name'] ?? '').toString()));
          final groups = <String>{
            for (final d in all)
              if ((d.data()['group'] ?? '').toString().isNotEmpty) d.data()['group'].toString()
          }.toList()
            ..sort();
          final list = all.where((d) {
            final m = d.data();
            if (group.isNotEmpty && m['group'] != group) return false;
            if (q.isNotEmpty &&
                !'${m['name']} ${m['phone']} ${m['address']} ${m['notes']}'
                    .toLowerCase()
                    .contains(q.toLowerCase())) {
              return false;
            }
            return true;
          }).toList();
          return ListView(padding: const EdgeInsets.only(bottom: 90), children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
              child: Row(children: [
                Expanded(
                  child: Pressable(
                    onTap: () => Navigator.push(
                        context, MaterialPageRoute(builder: (_) => const BroadcastScreen())),
                    child: Card(
                      margin: const EdgeInsets.all(4),
                      color: const Color(0xFF128C7E),
                      child: const Padding(
                        padding: EdgeInsets.all(12),
                        child: Row(children: [
                          Icon3D(Icons.campaign, size: 38, tone: tGreen, float: true),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text('رسالة واتساب\nلكل العملاء',
                                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                          ),
                        ]),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: Pressable(
                    onTap: all.isEmpty ? null : () => exportVcf(all),
                    child: const Card(
                      margin: EdgeInsets.all(4),
                      color: kPrimary,
                      child: Padding(
                        padding: EdgeInsets.all(12),
                        child: Row(children: [
                          Icon3D(Icons.contact_phone, size: 38, tone: tGold),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text('احفظ الأرقام\nعلى موبايلك',
                                style: TextStyle(color: kAccent, fontWeight: FontWeight.bold)),
                          ),
                        ]),
                      ),
                    ),
                  ),
                ),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: TextField(
                decoration: InputDecoration(
                    hintText: 'دوّر في ${all.length} عميل', prefixIcon: const Icon(Icons.search)),
                onChanged: (v) => setState(() => q = v.trim()),
              ),
            ),
            if (groups.isNotEmpty)
              SizedBox(
                height: 48,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(4),
                      child: ChoiceChip(
                          label: const Text('الكل'),
                          selected: group.isEmpty,
                          onSelected: (_) => setState(() => group = '')),
                    ),
                    for (final g in groups)
                      Padding(
                        padding: const EdgeInsets.all(4),
                        child: ChoiceChip(
                            label: Text(g),
                            selected: group == g,
                            onSelected: (_) => setState(() => group = g)),
                      ),
                  ],
                ),
              ),
            if (list.isEmpty)
              const EmptyView('ضيف عملاءك هنا: الاسم والعنوان ورقم التليفون\nحتى لو مش عندهم التطبيق',
                  icon: Icons.contacts),
            for (var i = 0; i < list.length; i++)
              FadeSlideIn(
                delayMs: i < 12 ? 30 * i : 0,
                child: Card(
                  child: ListTile(
                    onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => ContactForm(id: list[i].id, data: list[i].data()))),
                    leading: CircleAvatar(
                      backgroundColor: kPrimary,
                      child: Text(
                          (list[i].data()['name'] ?? '?').toString().isEmpty
                              ? '?'
                              : (list[i].data()['name'] ?? '?').toString().characters.first,
                          style: const TextStyle(color: kAccent, fontWeight: FontWeight.bold)),
                    ),
                    title: Text((list[i].data()['name'] ?? '').toString(),
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text([
                      (list[i].data()['phone'] ?? '').toString(),
                      if ((list[i].data()['address'] ?? '').toString().isNotEmpty)
                        list[i].data()['address'],
                      if ((list[i].data()['group'] ?? '').toString().isNotEmpty)
                        '🏷️ ${list[i].data()['group']}',
                    ].join('\n')),
                    isThreeLine: (list[i].data()['address'] ?? '').toString().isNotEmpty,
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      IconButton(
                        tooltip: 'واتساب',
                        icon: const Icon(Icons.message, color: Color(0xFF25D366)),
                        onPressed: () => openWhatsApp((list[i].data()['phone'] ?? '').toString()),
                      ),
                      IconButton(
                        tooltip: 'اتصال',
                        icon: const Icon(Icons.call, color: kPrimary),
                        onPressed: () => callNumber((list[i].data()['phone'] ?? '').toString()),
                      ),
                    ]),
                  ),
                ),
              ),
          ]);
        },
      ),
    );
  }
}

class ContactForm extends StatefulWidget {
  final String? id;
  final Map<String, dynamic>? data;
  const ContactForm({super.key, this.id, this.data});
  @override
  State<ContactForm> createState() => _ContactFormState();
}

class _ContactFormState extends State<ContactForm> {
  final name = TextEditingController();
  final phone = TextEditingController();
  final address = TextEditingController();
  final group = TextEditingController();
  final notes = TextEditingController();
  bool busy = false;

  @override
  void initState() {
    super.initState();
    final d = widget.data;
    if (d != null) {
      name.text = (d['name'] ?? '').toString();
      phone.text = (d['phone'] ?? '').toString();
      address.text = (d['address'] ?? '').toString();
      group.text = (d['group'] ?? '').toString();
      notes.text = (d['notes'] ?? '').toString();
    }
  }

  Future<void> save() async {
    if (name.text.trim().isEmpty || waNumber(phone.text).length < 10) {
      toast(context, 'اكتب الاسم ورقم تليفون صحيح', error: true);
      return;
    }
    setState(() => busy = true);
    final data = {
      'storeId': sid,
      'name': name.text.trim(),
      'phone': phone.text.trim(),
      'address': address.text.trim(),
      'group': group.text.trim(),
      'notes': notes.text.trim(),
    };
    try {
      if (widget.id == null) {
        await db.collection('contacts').add({...data, 'createdAt': FieldValue.serverTimestamp()});
      } else {
        await db.collection('contacts').doc(widget.id).update(data);
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) toast(context, '$e', error: true);
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.id == null ? 'عميل جديد' : 'بيانات العميل'),
        actions: [
          if (widget.id != null)
            IconButton(
              onPressed: () async {
                if (!await confirm(context, 'حذف العميل', 'متأكد؟')) return;
                await db.collection('contacts').doc(widget.id).delete();
                if (context.mounted) Navigator.pop(context);
              },
              icon: const Icon(Icons.delete_outline),
            ),
        ],
      ),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        const Center(child: Icon3D(Icons.person, size: 72, tone: tGold, circle: true, float: true)),
        const SizedBox(height: 18),
        _f(name, 'الاسم *', Icons.person_outline),
        _f(phone, 'رقم التليفون *', Icons.phone, ltr: true, type: TextInputType.phone),
        _f(address, 'العنوان', Icons.home_outlined, lines: 2),
        _f(group, 'مجموعة (اختياري) — زي: محلات المنيا، عملاء جملة', Icons.label_outline),
        _f(notes, 'ملاحظات', Icons.notes, lines: 3),
        if (widget.id != null)
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => openWhatsApp(phone.text),
                icon: const Icon(Icons.message, color: Color(0xFF25D366)),
                label: const Text('واتساب'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => callNumber(phone.text),
                icon: const Icon(Icons.call),
                label: const Text('اتصال'),
              ),
            ),
          ]),
        const SizedBox(height: 12),
        SizedBox(
          height: 48,
          child: FilledButton(onPressed: busy ? null : save, child: const Text('حفظ')),
        ),
      ]),
    );
  }

  Widget _f(TextEditingController c, String label, IconData icon,
          {bool ltr = false, int lines = 1, TextInputType? type}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(
          controller: c,
          maxLines: lines,
          keyboardType: type,
          textDirection: ltr ? TextDirection.ltr : null,
          decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon)),
        ),
      );
}

// ======================== رسالة جماعية على واتساب ========================

class BroadcastScreen extends StatefulWidget {
  const BroadcastScreen({super.key});
  @override
  State<BroadcastScreen> createState() => _BroadcastScreenState();
}

class _BroadcastScreenState extends State<BroadcastScreen> {
  final msg = TextEditingController();
  bool includeBook = true, includeApp = false;
  String group = '';
  List<Recipient> book = [], app = [];
  List<String> groups = [];
  bool loaded = false;

  // وضع الإرسال
  List<Recipient>? queue;
  int index = 0;
  final sent = <int>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await Future.wait([scoped('contacts').get(), scoped('users').get()]);
    if (!mounted) return;
    setState(() {
      book = [
        for (final d in r[0].docs)
          Recipient((d.data()['name'] ?? '').toString(), (d.data()['phone'] ?? '').toString(),
              (d.data()['group'] ?? '').toString())
      ];
      app = [
        for (final d in r[1].docs)
          if (d.data()['role'] != 'owner' && (d.data()['phone'] ?? '').toString().isNotEmpty)
            Recipient((d.data()['ownerName'] ?? d.data()['shopName'] ?? '').toString(),
                (d.data()['phone'] ?? '').toString())
      ];
      groups = {for (final b in book) if (b.group.isNotEmpty) b.group}.toList()..sort();
      loaded = true;
    });
  }

  List<Recipient> get recipients {
    final out = <Recipient>[];
    final seen = <String>{};
    void add(Recipient r) {
      final k = waNumber(r.phone);
      if (k.length < 10 || seen.contains(k)) return;
      seen.add(k);
      out.add(r);
    }

    if (includeBook) {
      for (final r in book) {
        if (group.isEmpty || r.group == group) add(r);
      }
    }
    if (includeApp) app.forEach(add);
    return out;
  }

  String textFor(Recipient r) => msg.text.replaceAll('{الاسم}', r.name.split(' ').first);

  Future<void> sendCurrent() async {
    final q = queue!;
    await openWhatsApp(q[index].phone, textFor(q[index]));
    setState(() {
      sent.add(index);
      if (index < q.length - 1) index++;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('رسالة جماعية واتساب')),
      body: !loaded ? const Loading() : (queue == null ? _compose() : _sending()),
    );
  }

  Widget _compose() {
    final r = recipients;
    return ListView(padding: const EdgeInsets.all(16), children: [
      TextField(
        controller: msg,
        maxLines: 6,
        onChanged: (_) => setState(() {}),
        decoration: const InputDecoration(
          labelText: 'الرسالة',
          hintText: 'أهلاً {الاسم} 👋\nعندنا عرض جديد على عطور SOL...',
          helperText: 'اكتب {الاسم} وهيتحط مكانها اسم كل عميل',
        ),
      ),
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: TextButton.icon(
          onPressed: () {
            msg.text = '${msg.text}{الاسم}';
            setState(() {});
          },
          icon: const Icon(Icons.person_pin),
          label: const Text('حط اسم العميل'),
        ),
      ),
      const SizedBox(height: 8),
      const Text('هتتبعت لمين؟', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
      CheckboxListTile(
        value: includeBook,
        onChanged: (v) => setState(() => includeBook = v ?? false),
        title: Text('دفتر العملاء (${book.length})'),
      ),
      if (includeBook && groups.isNotEmpty)
        Wrap(spacing: 6, children: [
          ChoiceChip(
              label: const Text('كل المجموعات'),
              selected: group.isEmpty,
              onSelected: (_) => setState(() => group = '')),
          for (final g in groups)
            ChoiceChip(label: Text(g), selected: group == g, onSelected: (_) => setState(() => group = g)),
        ]),
      CheckboxListTile(
        value: includeApp,
        onChanged: (v) => setState(() => includeApp = v ?? false),
        title: Text('عملاء التطبيق (${app.length})'),
      ),
      const SizedBox(height: 8),
      Card(
        color: const Color(0xFFE8F8F5),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
              'هتتبعت لـ ${r.length} رقم (من غير تكرار).\n'
              'واتساب مش بيسمح لأي تطبيق يبعت لوحده، فالتطبيق هيفتحلك محادثة كل واحد والرسالة جاهزة — تدوس إرسال وترجع تدوس "اللي بعده".',
              style: const TextStyle(height: 1.6)),
        ),
      ),
      if (msg.text.trim().isNotEmpty && r.isNotEmpty) ...[
        const SizedBox(height: 8),
        const Text('شكل الرسالة:', style: TextStyle(color: Colors.black54)),
        Container(
          margin: const EdgeInsets.only(top: 4),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
              color: const Color(0xFFDCF8C6), borderRadius: BorderRadius.circular(12)),
          child: Text(textFor(r.first)),
        ),
      ],
      const SizedBox(height: 16),
      SizedBox(
        height: 50,
        child: FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: const Color(0xFF128C7E)),
          onPressed: msg.text.trim().isEmpty || r.isEmpty
              ? null
              : () => setState(() {
                    queue = r;
                    index = 0;
                    sent.clear();
                  }),
          icon: const Icon(Icons.send),
          label: Text('ابدأ الإرسال لـ ${r.length}'),
        ),
      ),
    ]);
  }

  Widget _sending() {
    final q = queue!;
    final done = sent.length;
    final cur = q[index];
    final finished = done >= q.length;
    return Column(children: [
      LinearProgressIndicator(
          value: q.isEmpty ? 0 : done / q.length,
          minHeight: 8,
          color: const Color(0xFF25D366)),
      Padding(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          Text('اتبعت $done من ${q.length}',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          if (finished)
            const Column(children: [
              Icon3D(Icons.done_all, size: 80, tone: tGreen, circle: true, float: true),
              SizedBox(height: 10),
              Text('خلصت الإرسال للكل 🎉', style: TextStyle(fontSize: 18)),
            ])
          else ...[
            Card(
              margin: EdgeInsets.zero,
              child: ListTile(
                leading: const Icon3D(Icons.person, size: 44, tone: tGreen, circle: true),
                title: Text(cur.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text(cur.phone, textDirection: TextDirection.ltr),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 54,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: const Color(0xFF25D366)),
                onPressed: sendCurrent,
                icon: const Icon(Icons.send),
                label: Text(sent.contains(index) ? 'ابعت تاني' : 'ابعت لـ ${cur.name.split(' ').first}',
                    style: const TextStyle(fontSize: 17)),
              ),
            ),
            Row(children: [
              TextButton(
                  onPressed: index > 0 ? () => setState(() => index--) : null,
                  child: const Text('اللي قبله')),
              const Spacer(),
              TextButton(
                  onPressed: index < q.length - 1 ? () => setState(() => index++) : null,
                  child: const Text('تخطي ← اللي بعده')),
            ]),
          ],
        ]),
      ),
      Expanded(
        child: ListView.builder(
          itemCount: q.length,
          itemBuilder: (c, i) => ListTile(
            dense: true,
            selected: i == index,
            onTap: () => setState(() => index = i),
            leading: Icon(sent.contains(i) ? Icons.check_circle : Icons.radio_button_unchecked,
                color: sent.contains(i) ? const Color(0xFF25D366) : Colors.grey),
            title: Text(q[i].name),
            trailing: Text(q[i].phone, textDirection: TextDirection.ltr),
          ),
        ),
      ),
      SafeArea(
        child: TextButton(
            onPressed: () => setState(() => queue = null), child: const Text('رجوع للرسالة')),
      ),
    ]);
  }
}

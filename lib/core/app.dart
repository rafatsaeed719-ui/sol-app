import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

/// إيميل صاحب المنصة (المدير العام) — بيدير كل المحلات، وهو كمان صاحب محل SOL.
const String kAdminEmail = 'rafatsaeed719@gmail.com';
const String kBrand = 'SOL';

/// كود محل SOL الأساسي
const String kMainStore = 'sol';

/// الحسابات اللي المدير بيعملها باسم مستخدم بتتسجل داخلياً كـ username@sol-store.app
const String kUserDomain = 'sol-store.app';

String usernameToEmail(String username) =>
    '${username.trim().toLowerCase()}@$kUserDomain';

/// اللي اتكتب في خانة الدخول: لو فيه @ يبقى إيميل، غير كده يبقى اسم مستخدم
String loginToEmail(String input) {
  final t = input.trim();
  return t.contains('@') ? t : usernameToEmail(t);
}

bool validUsername(String u) => RegExp(r'^[a-zA-Z0-9._-]{3,30}$').hasMatch(u.trim());

const Color kPrimary = Color(0xFF141414); // أسود البراند
const Color kAccent = Color(0xFFC9A54C); // دهبي البراند
const Color kDanger = Color(0xFFC0392B);
const Color kSuccess = Color(0xFF1E8449);

final db = FirebaseFirestore.instance;
final auth = FirebaseAuth.instance;

String get uid => auth.currentUser?.uid ?? '';

/// المدير العام للمنصة
bool get isSuper =>
    (auth.currentUser?.email ?? '').toLowerCase() == kAdminEmail.toLowerCase();

/// بيانات الجلسة: المحل الحالي ودور المستخدم فيه
class Session {
  static String storeId = kMainStore;
  static String role = ''; // super / owner / customer
  static Map<String, dynamic> store = {};

  /// المدير العام بيقدر يدخل على أي محل
  static final ValueNotifier<String> superStore = ValueNotifier(kMainStore);

  static void reset() {
    storeId = kMainStore;
    role = '';
    store = {};
    superStore.value = kMainStore;
  }
}

/// مدير المحل الحالي (صاحب المحل أو المدير العام)
bool get isAdmin => isSuper || Session.role == 'owner';

/// كود المحل الحالي
String get sid => Session.storeId;

String get storeName {
  final n = (Session.store['name'] ?? '').toString();
  if (n.isNotEmpty) return n;
  return sid == kMainStore ? 'SOL Perfume' : sid;
}

String get storeSlogan {
  final n = (Session.store['slogan'] ?? '').toString();
  if (n.isNotEmpty) return n;
  return sid == kMainStore ? 'عطرك، بصمتك' : '';
}

/// استعلام على مجموعة متفلتر بالمحل الحالي
Query<Map<String, dynamic>> scoped(String collection) =>
    db.collection(collection).where('storeId', isEqualTo: sid);

/// إعدادات وعدّاد كل محل
DocumentReference<Map<String, dynamic>> storeMeta(String doc) =>
    db.collection('stores').doc(sid).collection('meta').doc(doc);

bool storeBlocked(Map<String, dynamic>? store) {
  if (store == null) return true;
  if (store['active'] != true) return true;
  final end = store['subscriptionEnd'];
  if (end is Timestamp && end.toDate().isBefore(DateTime.now())) return true;
  return false;
}

// ---------------- helpers ----------------

double toD(dynamic v) {
  if (v == null) return 0;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString()) ?? 0;
}

int toI(dynamic v) {
  if (v == null) return 0;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString()) ?? 0;
}

double round2(double v) => (v * 100).roundToDouble() / 100;

String _two(int n) => n.toString().padLeft(2, '0');

/// 1234.5 -> "1,234.5 ج"
String money(dynamic v) {
  final d = round2(toD(v));
  final neg = d < 0;
  final abs = d.abs();
  final whole = abs.truncate();
  final frac = ((abs - whole) * 100).round();
  final digits = whole.toString();
  final buf = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buf.write(',');
    buf.write(digits[i]);
  }
  var out = buf.toString();
  if (frac > 0) {
    out += '.${frac % 10 == 0 ? (frac ~/ 10).toString() : _two(frac)}';
  }
  return '${neg ? '-' : ''}$out ج';
}

/// 2026/10/11  أو  2026/10/11  02:30 م
String fmtDate(dynamic ts, {bool time = false}) {
  final d = tsToDate(ts);
  if (d == null) return '-';
  final date = '${d.year}/${_two(d.month)}/${_two(d.day)}';
  if (!time) return date;
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  return '$date  ${_two(h)}:${_two(d.minute)} ${d.hour < 12 ? 'ص' : 'م'}';
}

DateTime? tsToDate(dynamic ts) {
  if (ts is Timestamp) return ts.toDate();
  if (ts is DateTime) return ts;
  return null;
}

/// سعر الجملة (اللي المحل بيدفعه) = سعر البيع ناقص نسبة الخصم.
/// لو سعر البيع مش متسجل بيرجع للقيمة القديمة (fallback).
double netUnit(double sell, double discount, [double fallback = 0]) =>
    sell > 0 ? round2(sell * (1 - discount / 100)) : fallback;

/// المخزن: null يعني الصنف مش متتبع مخزنه
int? stockOf(Map<String, dynamic> p) => p['stock'] == null ? null : toI(p['stock']);

void toast(BuildContext context, String msg, {bool error = false}) {
  ScaffoldMessenger.of(context).hideCurrentSnackBar();
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(msg),
    backgroundColor: error ? kDanger : null,
  ));
}

Future<bool> confirm(BuildContext context, String title, String body) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('تأكيد')),
      ],
    ),
  );
  return r ?? false;
}

/// يختار صورة من المعرض/الكاميرا ويرجعها base64 مضغوطة
Future<String?> pickImageB64(BuildContext context, {double maxWidth = 600}) async {
  final src = await showModalBottomSheet<ImageSource>(
    context: context,
    builder: (c) => SafeArea(
      child: Wrap(children: [
        ListTile(
          leading: const Icon(Icons.photo_library),
          title: const Text('من المعرض'),
          onTap: () => Navigator.pop(c, ImageSource.gallery),
        ),
        ListTile(
          leading: const Icon(Icons.camera_alt),
          title: const Text('بالكاميرا'),
          onTap: () => Navigator.pop(c, ImageSource.camera),
        ),
      ]),
    ),
  );
  if (src == null) return null;
  final x = await ImagePicker()
      .pickImage(source: src, maxWidth: maxWidth, maxHeight: maxWidth, imageQuality: 55);
  if (x == null) return null;
  final bytes = await x.readAsBytes();
  return base64Encode(bytes);
}

final Map<String, Uint8List> _imgCache = {};

class B64Image extends StatelessWidget {
  final String? data;
  final double? width, height;
  final BoxFit fit;
  final IconData placeholder;
  const B64Image(this.data,
      {super.key,
      this.width,
      this.height,
      this.fit = BoxFit.cover,
      this.placeholder = Icons.inventory_2_outlined});

  @override
  Widget build(BuildContext context) {
    final d = data;
    if (d == null || d.isEmpty) {
      return Container(
        width: width,
        height: height,
        color: kPrimary.withValues(alpha: 0.07),
        child: Icon(placeholder, color: kPrimary.withValues(alpha: 0.4), size: 36),
      );
    }
    final key = '${d.length}_${d.hashCode}';
    final bytes = _imgCache.putIfAbsent(key, () => base64Decode(d));
    return Image.memory(bytes, width: width, height: height, fit: fit, gaplessPlayback: true);
  }
}

class Avatar extends StatelessWidget {
  final String? photo;
  final double radius;
  const Avatar(this.photo, {super.key, this.radius = 22});
  @override
  Widget build(BuildContext context) {
    return ClipOval(
      child: B64Image(photo,
          width: radius * 2, height: radius * 2, placeholder: Icons.storefront),
    );
  }
}

class EmptyView extends StatelessWidget {
  final String text;
  final IconData icon;
  const EmptyView(this.text, {super.key, this.icon = Icons.inbox_outlined});
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 56, color: Colors.grey),
          const SizedBox(height: 12),
          Text(text, textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey)),
        ]),
      ),
    );
  }
}

class Loading extends StatelessWidget {
  const Loading({super.key});
  @override
  Widget build(BuildContext context) =>
      const Center(child: CircularProgressIndicator());
}

class StatTile extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final IconData icon;
  final VoidCallback? onTap;
  const StatTile(this.label, this.value,
      {super.key, this.color = kPrimary, this.icon = Icons.info_outline, this.onTap});
  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 6),
              Expanded(
                  child: Text(label,
                      style: const TextStyle(fontSize: 12, color: Colors.black54),
                      overflow: TextOverflow.ellipsis)),
            ]),
            const SizedBox(height: 6),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerStart,
              child: Text(value,
                  style: TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold, color: color)),
            ),
          ]),
        ),
      ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  final String text;
  final Widget? trailing;
  const SectionTitle(this.text, {super.key, this.trailing});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
      child: Row(children: [
        Expanded(
            child: Text(text,
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.bold, color: kPrimary))),
        if (trailing != null) trailing!,
      ]),
    );
  }
}

Widget statusChip(String status) {
  const map = {
    'new': ['جديد', Colors.blue],
    'accepted': ['تم القبول', Colors.orange],
    'invoiced': ['اتعمله فاتورة', kSuccess],
    'cancelled': ['ملغي', Colors.grey],
  };
  final m = map[status] ?? [status, Colors.grey];
  final c = m[1] as Color;
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
    child: Text(m[0] as String,
        style: TextStyle(color: c, fontSize: 12, fontWeight: FontWeight.bold)),
  );
}


/// لوجو المحل الحالي (أو لوجو SOL لمحل SOL)
class StoreLogo extends StatelessWidget {
  final double size;
  final double radius;
  final Map<String, dynamic>? store;
  final String? storeId;
  const StoreLogo({super.key, this.size = 80, this.radius = 12, this.store, this.storeId});

  @override
  Widget build(BuildContext context) {
    final st = store ?? Session.store;
    final id = storeId ?? sid;
    final logo = (st['logo'] ?? '').toString();
    Widget child;
    if (logo.isNotEmpty) {
      child = B64Image(logo, width: size, height: size);
    } else if (id == kMainStore) {
      child = Image.asset('assets/logo.png', width: size, height: size, fit: BoxFit.cover);
    } else {
      final n = (st['name'] ?? id).toString();
      child = Container(
        width: size,
        height: size,
        color: kPrimary,
        alignment: Alignment.center,
        child: Text(n.isEmpty ? '?' : n.characters.first.toUpperCase(),
            style: TextStyle(
                color: kAccent, fontSize: size * 0.45, fontWeight: FontWeight.bold)),
      );
    }
    return ClipRRect(borderRadius: BorderRadius.circular(radius), child: child);
  }
}

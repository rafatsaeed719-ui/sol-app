import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart' as intl;

/// إيميل المدير — أي حد يدخل بالإيميل ده يفتح له لوحة التحكم.
const String kAdminEmail = 'rafatsaeed719@gmail.com';
const String kBrand = 'SOL';

const Color kPrimary = Color(0xFF0B3C5D);
const Color kAccent = Color(0xFFF2A541);
const Color kDanger = Color(0xFFC0392B);
const Color kSuccess = Color(0xFF1E8449);

final db = FirebaseFirestore.instance;
final auth = FirebaseAuth.instance;

bool get isAdmin =>
    (auth.currentUser?.email ?? '').toLowerCase() == kAdminEmail.toLowerCase();
String get uid => auth.currentUser?.uid ?? '';

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

String money(dynamic v) {
  final d = toD(v);
  final f = intl.NumberFormat('#,##0.##', 'en');
  return '${f.format(d)} ج';
}

String fmtDate(dynamic ts, {bool time = false}) {
  DateTime? d;
  if (ts is Timestamp) d = ts.toDate();
  if (ts is DateTime) d = ts;
  if (d == null) return '-';
  return intl.DateFormat(time ? 'yyyy/MM/dd  hh:mm a' : 'yyyy/MM/dd', 'en')
      .format(d);
}

DateTime? tsToDate(dynamic ts) {
  if (ts is Timestamp) return ts.toDate();
  if (ts is DateTime) return ts;
  return null;
}

/// سعر الوحدة الصافي للمحل = سعر الجملة بعد خصم النسبة
double netUnit(double wholesale, double discount) =>
    round2(wholesale * (1 - discount / 100));

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

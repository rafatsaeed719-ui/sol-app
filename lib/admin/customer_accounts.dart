import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';

import '../auth/location_picker.dart';
import '../auth/login_screen.dart';
import '../core/app.dart';
import '../core/data.dart';
import '../firebase_options.dart';
import 'dashboard_screen.dart';

/// نسخة Firebase تانية عشان المدير يعمل حسابات من غير ما يخرج من حسابه
Future<FirebaseAuth> _helperAuth() async {
  const name = 'sol-admin-helper';
  FirebaseApp app;
  try {
    app = Firebase.app(name);
  } catch (_) {
    app = await Firebase.initializeApp(name: name, options: solFirebaseOptions);
  }
  return FirebaseAuth.instanceFor(app: app);
}

String randomPassword() {
  final r = Random.secure();
  return (100000 + r.nextInt(900000)).toString();
}

/// المدير يعمل حساب محل جديد باسم مستخدم وكلمة سر
Future<String> createCustomerAccount({
  required String username,
  required String password,
  required Map<String, dynamic> profile,
}) async {
  final helper = await _helperAuth();
  final cred = await helper.createUserWithEmailAndPassword(
      email: usernameToEmail(username), password: password);
  final newUid = cred.user!.uid;
  await helper.signOut();
  await db.collection('users').doc(newUid).set({
    ...profile,
    'username': username.trim().toLowerCase(),
    'password': password,
    'email': usernameToEmail(username),
    'createdByAdmin': true,
    'storeId': profile['storeId'] ?? sid,
    'role': profile['role'] ?? 'customer',
    'points': 0,
    'createdAt': FieldValue.serverTimestamp(),
  });
  return newUid;
}

/// تغيير كلمة سر أي حساب (لازم تكون كلمة السر الحالية متسجلة عندنا)
Future<void> changeUserPassword(
    String userId, String loginEmail, String oldPass, String newPass) async {
  final helper = await _helperAuth();
  final cred = await helper.signInWithEmailAndPassword(email: loginEmail, password: oldPass);
  await cred.user!.updatePassword(newPass);
  await helper.signOut();
  await db.collection('users').doc(userId).update({'password': newPass});
}

Future<void> changeCustomerPassword(
        String customerId, String username, String oldPass, String newPass) =>
    changeUserPassword(customerId, usernameToEmail(username), oldPass, newPass);

/// الإيميل اللي الحساب بيدخل بيه
String loginEmailOf(Map<String, dynamic> m) {
  final e = (m['email'] ?? '').toString();
  if (e.isNotEmpty) return e;
  final u = (m['username'] ?? '').toString();
  return u.isEmpty ? '' : usernameToEmail(u);
}

String credentialsText(String shop, String username, String password) =>
    'أهلاً بيك في $storeName ✨\n'
    'دي بيانات دخولك على التطبيق ($shop):\n'
    'اسم المستخدم: $username\n'
    'كلمة السر: $password';

Future<void> showCredentials(BuildContext context,
    {required String shop,
    required String username,
    required String password,
    String phone = ''}) {
  final text = credentialsText(shop, username, password);
  return showDialog(
    context: context,
    builder: (c) => AlertDialog(
      icon: const Icon(Icons.verified_user, color: kSuccess, size: 44),
      title: const Text('بيانات دخول العميل'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        _credRow('اسم المستخدم', username),
        _credRow('كلمة السر', password),
        const SizedBox(height: 8),
        const Text('ابعتهم للعميل يدخل بيهم من شاشة الدخول',
            style: TextStyle(color: Colors.black54, fontSize: 12)),
      ]),
      actions: [
        TextButton.icon(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: text));
            if (c.mounted) toast(c, 'اتنسخت البيانات');
          },
          icon: const Icon(Icons.copy),
          label: const Text('نسخ'),
        ),
        if (phone.isNotEmpty)
          FilledButton.icon(
            onPressed: () => whatsapp(phone, text),
            icon: const Icon(Icons.message),
            label: const Text('واتساب'),
          ),
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('تمام')),
      ],
    ),
  );
}

Widget _credRow(String k, String v) => Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
          color: kAccent.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
      child: Row(children: [
        Text(k, style: const TextStyle(color: Colors.black54)),
        const Spacer(),
        SelectableText(v,
            textDirection: TextDirection.ltr,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
      ]),
    );

// ======================== شاشة إضافة عميل ========================

class AddCustomerScreen extends StatefulWidget {
  const AddCustomerScreen({super.key});
  @override
  State<AddCustomerScreen> createState() => _AddCustomerScreenState();
}

class _AddCustomerScreenState extends State<AddCustomerScreen> {
  final shop = TextEditingController();
  final owner = TextEditingController();
  final phone = TextEditingController();
  final address = TextEditingController();
  final username = TextEditingController();
  final password = TextEditingController(text: randomPassword());
  final welcome = TextEditingController();
  String? photo;
  LatLng? location;
  bool busy = false;

  Future<void> save() async {
    if (shop.text.trim().isEmpty) {
      toast(context, 'اكتب اسم المحل', error: true);
      return;
    }
    final digits = normalizeLogin(phone.text.replaceAll(RegExp(r'[^0-9+]'), ''));
    if (username.text.trim().isEmpty) username.text = digits;
    if (username.text.trim().isEmpty) {
      toast(context, 'اكتب رقم الموبايل — العميل هيدخل بيه', error: true);
      return;
    }
    if (!validUsername(username.text)) {
      toast(context, 'اسم المستخدم بالإنجليزي أو أرقام، من 3 حروف على الأقل ومن غير مسافات',
          error: true);
      return;
    }
    if (password.text.length < 6) {
      toast(context, 'كلمة السر 6 حروف أو أرقام على الأقل', error: true);
      return;
    }
    setState(() => busy = true);
    try {
      await createCustomerAccount(
        username: username.text,
        password: password.text,
        profile: {
          'shopName': shop.text.trim(),
          'ownerName': owner.text.trim(),
          'phone': phone.text.trim(),
          'address': address.text.trim(),
          'photo': photo ?? '',
          if (location != null) 'lat': location!.latitude,
          if (location != null) 'lng': location!.longitude,
          if (welcome.text.trim().isNotEmpty)
            'personalMessage': {
              'title': 'أهلاً بيك في $storeName ✨',
              'text': welcome.text.trim(),
              'at': Timestamp.now(),
            },
        },
      );
      if (!mounted) return;
      await showCredentials(context,
          shop: shop.text.trim(),
          username: username.text.trim().toLowerCase(),
          password: password.text,
          phone: phone.text.trim());
      if (mounted) Navigator.pop(context);
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        toast(
            context,
            e.code == 'email-already-in-use'
                ? 'الرقم أو اسم المستخدم ده متسجل قبل كده'
                : authError(e),
            error: true);
      }
    } catch (e) {
      if (mounted) toast(context, '$e', error: true);
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('إضافة عميل جديد')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Center(
          child: GestureDetector(
            onTap: () async {
              final p = await pickImageB64(context, maxWidth: 400);
              if (p != null) setState(() => photo = p);
            },
            child: Stack(children: [
              Avatar(photo, radius: 44),
              const Positioned(
                bottom: 0,
                right: 0,
                child: CircleAvatar(
                    radius: 14,
                    backgroundColor: kAccent,
                    child: Icon(Icons.camera_alt, size: 16, color: Colors.white)),
              ),
            ]),
          ),
        ),
        const SizedBox(height: 16),
        _f(shop, 'اسم المحل *', Icons.storefront),
        _f(owner, 'اسم صاحب المحل', Icons.person_outline),
        _f(phone, 'رقم الموبايل * (العميل هيدخل بيه)', Icons.phone,
            type: TextInputType.phone, ltr: true),
        _f(address, 'العنوان', Icons.home_outlined),
        Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: ListTile(
            leading: Icon(Icons.location_on, color: location == null ? Colors.grey : kSuccess),
            title: Text(location == null
                ? 'حدد مكان المحل (لو إنت في المحل دوس "موقعي")'
                : 'تم تحديد المكان ✔'),
            trailing: const Icon(Icons.map),
            onTap: () async {
              final p = await Navigator.push<LatLng>(context,
                  MaterialPageRoute(builder: (_) => LocationPicker(initial: location)));
              if (p != null) setState(() => location = p);
            },
          ),
        ),
        const Divider(height: 24),
        const Text('🔐 بيانات الدخول',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        const SizedBox(height: 10),
        _f(username, 'اسم المستخدم (اختياري — لو فاضي هيدخل برقم الموبايل)', Icons.badge_outlined,
            ltr: true),
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: TextField(
            controller: password,
            textDirection: TextDirection.ltr,
            decoration: InputDecoration(
              labelText: 'كلمة السر *',
              prefixIcon: const Icon(Icons.lock_outline),
              suffixIcon: IconButton(
                tooltip: 'كلمة سر جديدة',
                onPressed: () => setState(() => password.text = randomPassword()),
                icon: const Icon(Icons.refresh),
              ),
            ),
          ),
        ),
        const Divider(height: 24),
        const Text('💌 رسالة ترحيب خاصة (اختياري)',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        const SizedBox(height: 8),
        TextField(
          controller: welcome,
          maxLines: 3,
          decoration: const InputDecoration(
              hintText: 'هتظهرله أول ما يفتح التطبيق — مثلاً: نورتنا يا حاج محمد، عندك خصم 5% على أول طلب'),
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 48,
          child: FilledButton.icon(
            onPressed: busy ? null : save,
            icon: busy
                ? const SizedBox(
                    width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.person_add),
            label: const Text('إنشاء الحساب', style: TextStyle(fontSize: 16)),
          ),
        ),
      ]),
    );
  }

  Widget _f(TextEditingController c, String label, IconData icon,
          {TextInputType? type, bool ltr = false}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(
          controller: c,
          keyboardType: type,
          textDirection: ltr ? TextDirection.ltr : null,
          decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon)),
        ),
      );
}

// ======================== كارت بيانات الدخول في صفحة العميل ========================

/// حذف عميل: لو كلمة السر متسجلة بنمسح حسابه خالص، غير كده بنوقفه ونخفيه
Future<bool> deleteCustomer(String id, Map<String, dynamic> m) async {
  final email = loginEmailOf(m);
  final pass = (m['password'] ?? '').toString();
  if (email.isNotEmpty && pass.isNotEmpty) {
    try {
      final helper = await _helperAuth();
      final cred = await helper.signInWithEmailAndPassword(email: email, password: pass);
      await cred.user!.delete();
      await helper.signOut();
      await db.collection('users').doc(id).delete();
      return true;
    } catch (_) {}
  }
  await db.collection('users').doc(id).update({'deleted': true, 'disabled': true});
  return false;
}

class CredentialsCard extends StatelessWidget {
  final String customerId;
  final Map<String, dynamic> m;
  const CredentialsCard({super.key, required this.customerId, required this.m});

  String get loginId {
    final u = (m['username'] ?? '').toString();
    if (u.isNotEmpty) return u;
    return (m['email'] ?? '').toString();
  }

  Future<void> _change(BuildContext context) async {
    final c = TextEditingController(text: randomPassword());
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('كلمة سر جديدة'),
        content: TextField(
          controller: c,
          textDirection: TextDirection.ltr,
          decoration: const InputDecoration(labelText: 'كلمة السر الجديدة (6 على الأقل)'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('تغيير')),
        ],
      ),
    );
    if (ok != true) return;
    if (c.text.length < 6) {
      if (context.mounted) toast(context, 'كلمة السر 6 على الأقل', error: true);
      return;
    }
    try {
      await changeUserPassword(customerId, loginEmailOf(m), m['password'] ?? '', c.text);
      if (context.mounted) {
        await showCredentials(context,
            shop: m['shopName'] ?? '',
            username: loginId,
            password: c.text,
            phone: m['phone'] ?? '');
      }
    } catch (e) {
      if (context.mounted) toast(context, 'مقدرناش نغيرها: $e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = loginId;
    final pass = (m['password'] ?? '').toString();
    final realEmail = user.contains('@') && !user.endsWith('@$kUserDomain');
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('🔐 بيانات الدخول', style: TextStyle(fontWeight: FontWeight.bold)),
          _credRow('بيدخل بـ', user.isEmpty ? '—' : user),
          _credRow('كلمة السر', pass.isEmpty ? 'مش متسجلة' : pass),
          Wrap(spacing: 8, children: [
            if (pass.isNotEmpty)
              TextButton.icon(
                onPressed: () => showCredentials(context,
                    shop: m['shopName'] ?? '',
                    username: user,
                    password: pass,
                    phone: m['phone'] ?? ''),
                icon: const Icon(Icons.share),
                label: const Text('ابعتها للعميل'),
              ),
            if (pass.isNotEmpty)
              TextButton.icon(
                onPressed: () => _change(context),
                icon: const Icon(Icons.lock_reset),
                label: const Text('تغيير كلمة السر'),
              ),
            if (pass.isEmpty && realEmail)
              TextButton.icon(
                onPressed: () async {
                  await auth.sendPasswordResetEmail(email: user);
                  if (context.mounted) toast(context, 'اتبعتله رسالة على الإيميل يغيّر منها كلمة السر');
                },
                icon: const Icon(Icons.mark_email_read),
                label: const Text('ابعتله رسالة تغيير كلمة السر'),
              ),
          ]),
          if (pass.isEmpty && !realEmail)
            const Text(
                'العميل ده سجّل بنفسه قبل ما نحفظ كلمات السر، فمينفعش تتغير من هنا. لو نسيها: احذفه واعمله حساب جديد برقم موبايله.',
                style: TextStyle(fontSize: 12, color: Colors.black54)),
        ]),
      ),
    );
  }
}

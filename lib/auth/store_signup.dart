import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../core/app.dart';
import '../core/platform.dart';
import 'login_screen.dart';

/// محل جديد عاوز يشترك في البرنامج: يختار باقة ويعمل حسابه، والمدير العام يفعّله بعد الدفع
class StoreSignupScreen extends StatefulWidget {
  const StoreSignupScreen({super.key});
  @override
  State<StoreSignupScreen> createState() => _StoreSignupScreenState();
}

class _StoreSignupScreenState extends State<StoreSignupScreen> {
  final name = TextEditingController();
  final code = TextEditingController();
  final owner = TextEditingController();
  final phone = TextEditingController();
  final address = TextEditingController();
  final username = TextEditingController();
  final pass = TextEditingController();
  String? logo;
  int planIndex = -1;
  bool busy = false;

  Future<void> submit(PlatformConfig cfg) async {
    final id = code.text.trim().toLowerCase();
    if (planIndex < 0) {
      toast(context, 'اختار الباقة الأول', error: true);
      return;
    }
    if (name.text.trim().isEmpty || phone.text.trim().isEmpty) {
      toast(context, 'اكتب اسم المحل ورقم الموبايل', error: true);
      return;
    }
    if (!RegExp(r'^[a-z0-9_-]{2,20}$').hasMatch(id)) {
      toast(context, 'كود المحل بالإنجليزي الصغير أو أرقام من غير مسافات (زي ahmed1)',
          error: true);
      return;
    }
    if (!validUsername(username.text) || pass.text.length < 6) {
      toast(context, 'اسم مستخدم بالإنجليزي وكلمة سر 6 على الأقل', error: true);
      return;
    }
    setState(() => busy = true);
    try {
      final ref = db.collection('stores').doc(id);
      if ((await ref.get()).exists) throw 'كود المحل ده متاخد — اختار كود تاني';
      final cred = await auth.createUserWithEmailAndPassword(
          email: usernameToEmail(username.text), password: pass.text);
      final myUid = cred.user!.uid;
      final plan = cfg.plans[planIndex];
      await ref.set({
        'name': name.text.trim(),
        'slogan': '',
        'phone': phone.text.trim(),
        'address': address.text.trim(),
        'logo': logo ?? '',
        'active': false,
        'status': 'pending',
        'requestedPlan': plan.toMap(),
        'ownerUid': myUid,
        'ownerUsername': username.text.trim().toLowerCase(),
        'createdAt': FieldValue.serverTimestamp(),
      });
      await db.collection('users').doc(myUid).set({
        'storeId': id,
        'role': 'owner',
        'shopName': name.text.trim(),
        'ownerName': owner.text.trim(),
        'phone': phone.text.trim(),
        'address': address.text.trim(),
        'photo': logo ?? '',
        'username': username.text.trim().toLowerCase(),
        'password': pass.text,
        'email': usernameToEmail(username.text),
        'points': 0,
        'createdAt': FieldValue.serverTimestamp(),
      });
      await db.collection('notifications').add({
        'to': 'super',
        'storeId': id,
        'title': 'طلب اشتراك جديد 🏪',
        'body': '${name.text.trim()} طالب باقة ${plan.name} (${money(plan.price)}) — ${phone.text.trim()}',
        'type': 'store',
        'refId': id,
        'createdAt': FieldValue.serverTimestamp(),
      });
      if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        toast(context,
            e.code == 'email-already-in-use' ? 'اسم المستخدم ده متاخد — اختار اسم تاني' : authError(e),
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
      appBar: AppBar(title: const Text('اشترك بمحلك في SOL')),
      body: StreamBuilder<PlatformConfig>(
        stream: platformStream(),
        builder: (context, snap) {
          if (!snap.hasData) return const Loading();
          final cfg = snap.data!;
          if (!cfg.signupOpen) {
            return const EmptyView('الاشتراك مقفول دلوقتي — كلّم إدارة SOL',
                icon: Icons.lock_outline);
          }
          return ListView(padding: const EdgeInsets.all(16), children: [
            const Text('شغّل محلك على التطبيق: أصنافك، عملاءك، فواتيرك، مخزنك، ومصروفاتك — كله في مكان واحد وباسم محلك ولوجو بتاعك.',
                style: TextStyle(fontSize: 15, height: 1.6)),
            const SizedBox(height: 14),
            const Text('١) اختار الباقة',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: kPrimary)),
            const SizedBox(height: 8),
            for (var i = 0; i < cfg.plans.length; i++)
              Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(
                      color: planIndex == i ? kAccent : Colors.grey.shade200,
                      width: planIndex == i ? 2 : 1),
                ),
                color: planIndex == i ? const Color(0xFFFFF6E6) : null,
                child: ListTile(
                  onTap: () => setState(() => planIndex = i),
                  leading: Icon(planIndex == i ? Icons.radio_button_checked : Icons.radio_button_off,
                      color: kAccent),
                  title: Text(cfg.plans[i].name,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  subtitle: Text('${cfg.plans[i].period}${cfg.plans[i].note.isEmpty ? '' : '  •  ${cfg.plans[i].note}'}'),
                  trailing: Text(money(cfg.plans[i].price),
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold, color: kSuccess)),
                ),
              ),
            if (cfg.paymentInfo.isNotEmpty)
              Card(
                color: kPrimary,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Icon(Icons.payments, color: kAccent),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text('طريقة الدفع:\n${cfg.paymentInfo}',
                          style: const TextStyle(color: Colors.white, height: 1.5)),
                    ),
                  ]),
                ),
              ),
            const SizedBox(height: 14),
            const Text('٢) بيانات المحل',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: kPrimary)),
            const SizedBox(height: 8),
            Center(
              child: GestureDetector(
                onTap: () async {
                  final p = await pickImageB64(context, maxWidth: 500);
                  if (p != null) setState(() => logo = p);
                },
                child: Column(children: [
                  StoreLogo(size: 90, store: {'logo': logo, 'name': name.text}, storeId: '?'),
                  const SizedBox(height: 4),
                  const Text('لوجو المحل (اختياري)', style: TextStyle(color: Colors.black54)),
                ]),
              ),
            ),
            const SizedBox(height: 12),
            _f(name, 'اسم المحل *', Icons.store, onChanged: (_) => setState(() {})),
            _f(code, 'كود المحل * (إنجليزي — عملاءك هيكتبوه)', Icons.qr_code, ltr: true),
            _f(owner, 'اسمك', Icons.person_outline),
            _f(phone, 'رقم الموبايل *', Icons.phone, ltr: true),
            _f(address, 'العنوان', Icons.home_outlined),
            const SizedBox(height: 6),
            const Text('٣) بيانات الدخول',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: kPrimary)),
            const SizedBox(height: 8),
            _f(username, 'اسم المستخدم * (إنجليزي)', Icons.badge_outlined, ltr: true),
            _f(pass, 'كلمة السر * (6 على الأقل)', Icons.lock_outline, ltr: true, obscure: true),
            const SizedBox(height: 8),
            SizedBox(
              height: 50,
              child: FilledButton.icon(
                onPressed: busy ? null : () => submit(cfg),
                icon: busy
                    ? const SizedBox(
                        width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.send),
                label: Text(planIndex < 0
                    ? 'ابعت طلب الاشتراك'
                    : 'ابعت الطلب — ${cfg.plans[planIndex].name} ${money(cfg.plans[planIndex].price)}'),
              ),
            ),
            const SizedBox(height: 8),
            const Text('بعد ما تدفع، إدارة SOL هتفعّل حسابك وتقدر تبدأ على طول.',
                textAlign: TextAlign.center, style: TextStyle(color: Colors.black54)),
          ]);
        },
      ),
    );
  }

  Widget _f(TextEditingController c, String label, IconData icon,
          {bool ltr = false, bool obscure = false, ValueChanged<String>? onChanged}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(
          controller: c,
          obscureText: obscure,
          onChanged: onChanged,
          textDirection: ltr ? TextDirection.ltr : null,
          decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon)),
        ),
      );
}

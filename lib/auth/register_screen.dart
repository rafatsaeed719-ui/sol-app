import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../core/app.dart';
import '../core/data.dart';
import 'location_picker.dart';
import 'login_screen.dart';

/// تسجيل محل جديد — أو تعديل بيانات المحل لو existing موجود
class RegisterScreen extends StatefulWidget {
  final bool completeProfileOnly;
  final Map<String, dynamic>? existing; // وضع التعديل
  const RegisterScreen({super.key, this.completeProfileOnly = false, this.existing});
  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final shop = TextEditingController();
  final owner = TextEditingController();
  final phone = TextEditingController();
  final address = TextEditingController();
  final email = TextEditingController();
  final pass = TextEditingController();
  final storeCode = TextEditingController(text: kMainStore);
  String? photo;
  LatLng? location;
  bool busy = false;

  bool get editMode => widget.existing != null;
  bool get needAccount => !widget.completeProfileOnly && !editMode;
  bool get adminEmailTyped =>
      email.text.trim().toLowerCase() == kAdminEmail.toLowerCase();

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      shop.text = e['shopName'] ?? '';
      owner.text = e['ownerName'] ?? '';
      phone.text = e['phone'] ?? '';
      address.text = e['address'] ?? '';
      photo = e['photo'];
      if (e['lat'] != null) location = LatLng(toD(e['lat']), toD(e['lng']));
    }
    email.addListener(() => setState(() {}));
  }

  Future<void> pickLocation() async {
    final p = await Navigator.push<LatLng>(
        context, MaterialPageRoute(builder: (_) => LocationPicker(initial: location)));
    if (p != null) setState(() => location = p);
  }

  Future<void> submit() async {
    final adminOnly = needAccount && adminEmailTyped;
    if (!adminOnly) {
      if (shop.text.trim().isEmpty || owner.text.trim().isEmpty || phone.text.trim().isEmpty) {
        toast(context, 'اكتب اسم المحل واسم صاحبه ورقم الموبايل', error: true);
        return;
      }
      if (location == null) {
        toast(context, 'حدد مكان المحل على الخريطة', error: true);
        return;
      }
    }
    if (needAccount && (email.text.trim().isEmpty || pass.text.length < 6)) {
      toast(context, 'اكتب الإيميل وباسورد 6 حروف على الأقل', error: true);
      return;
    }
    setState(() => busy = true);
    try {
      if (!editMode && !adminOnly) {
        final code = storeCode.text.trim().toLowerCase();
        final st = code.isEmpty ? null : await db.collection('stores').doc(code).get();
        if (st == null || !st.exists) throw 'كود المحل غلط — اسأل المحل اللي بتتعامل معاه عن الكود';
        if (storeBlocked(st.data())) throw 'المحل ده مش متاح دلوقتي';
        Session.storeId = code;
        Session.store = st.data()!;
      }
      if (needAccount) {
        if (!email.text.contains('@') && !validUsername(email.text)) {
          throw 'اسم المستخدم بالإنجليزي أو أرقام من غير مسافات (3 حروف على الأقل)';
        }
        await auth.createUserWithEmailAndPassword(
            email: loginToEmail(email.text), password: pass.text);
      }
      if (!isAdmin) {
        final data = <String, dynamic>{
          'shopName': shop.text.trim(),
          'ownerName': owner.text.trim(),
          'phone': phone.text.trim(),
          'address': address.text.trim(),
          'photo': photo ?? '',
          'lat': location!.latitude,
          'lng': location!.longitude,
          'email': auth.currentUser?.email ?? '',
          if (needAccount && !email.text.contains('@'))
            'username': email.text.trim().toLowerCase(),
          if (needAccount) 'password': pass.text,
        };
        final ref = db.collection('users').doc(uid);
        if (editMode) {
          await ref.update(data);
        } else {
          await ref.set({
            ...data,
            'storeId': sid,
            'role': 'customer',
            'points': 0,
            'createdAt': FieldValue.serverTimestamp(),
          });
          await notify('admin', 'محل جديد سجّل 🏪',
              '${data['shopName']} — ${data['ownerName']} (${data['phone']})',
              type: 'customer', refId: uid);
        }
      }
      if (!mounted) return;
      if (editMode) {
        toast(context, 'اتحفظت البيانات');
        Navigator.pop(context);
      } else {
        Navigator.of(context).popUntil((r) => r.isFirst);
      }
    } catch (e) {
      if (mounted) toast(context, authError(e), error: true);
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final adminOnly = needAccount && adminEmailTyped;
    return Scaffold(
      appBar: AppBar(
        title: Text(editMode ? 'تعديل بيانات المحل' : 'تسجيل محل جديد'),
        actions: [
          if (widget.completeProfileOnly)
            IconButton(
                tooltip: 'خروج',
                onPressed: () => auth.signOut(),
                icon: const Icon(Icons.logout)),
        ],
      ),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        if (!editMode && !adminOnly) ...[
          _f(storeCode, 'كود المحل اللي بتتعامل معاه *', Icons.qr_code, ltr: true),
          const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: Text('لو بتتعامل مع SOL سيبه sol — لو محل تاني اسأله عن الكود بتاعه',
                style: TextStyle(fontSize: 12, color: Colors.black54)),
          ),
        ],
        if (!adminOnly) ...[
          Center(
            child: GestureDetector(
              onTap: () async {
                final p = await pickImageB64(context, maxWidth: 400);
                if (p != null) setState(() => photo = p);
              },
              child: Stack(children: [
                Avatar(photo, radius: 50),
                const Positioned(
                  bottom: 0,
                  right: 0,
                  child: CircleAvatar(
                      radius: 16,
                      backgroundColor: kAccent,
                      child: Icon(Icons.camera_alt, size: 18, color: Colors.white)),
                ),
              ]),
            ),
          ),
          const Center(
              child: Padding(
            padding: EdgeInsets.all(6),
            child: Text('صورة المحل', style: TextStyle(color: Colors.black54)),
          )),
          const SizedBox(height: 8),
          _f(shop, 'اسم المحل *', Icons.storefront),
          _f(owner, 'اسم صاحب المحل *', Icons.person_outline),
          _f(phone, 'رقم الموبايل *', Icons.phone, type: TextInputType.phone, ltr: true),
          _f(address, 'العنوان بالتفصيل', Icons.home_outlined),
          Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: ListTile(
              leading: Icon(Icons.location_on,
                  color: location == null ? kDanger : kSuccess),
              title: Text(location == null
                  ? 'حدد مكان المحل على الخريطة *'
                  : 'تم تحديد المكان ✔'),
              subtitle: location == null
                  ? null
                  : Text(
                      '${location!.latitude.toStringAsFixed(5)}, ${location!.longitude.toStringAsFixed(5)}',
                      textDirection: TextDirection.ltr),
              trailing: const Icon(Icons.map),
              onTap: pickLocation,
            ),
          ),
        ],
        if (needAccount) ...[
          _f(email, 'الإيميل أو اسم مستخدم *', Icons.email_outlined,
              type: TextInputType.emailAddress, ltr: true),
          _f(pass, 'الباسورد * (6 على الأقل)', Icons.lock_outline,
              obscure: true, ltr: true),
          if (adminOnly)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(12),
                child: Text('ده إيميل المدير — هيتعمل حساب المدير ولوحة التحكم.'),
              ),
            ),
        ],
        const SizedBox(height: 10),
        SizedBox(
          height: 48,
          child: FilledButton(
            onPressed: busy ? null : submit,
            child: busy
                ? const SizedBox(
                    width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                : Text(editMode ? 'حفظ' : 'تسجيل', style: const TextStyle(fontSize: 16)),
          ),
        ),
      ]),
    );
  }

  Widget _f(TextEditingController c, String label, IconData icon,
      {TextInputType? type, bool obscure = false, bool ltr = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: c,
        keyboardType: type,
        obscureText: obscure,
        textDirection: ltr ? TextDirection.ltr : null,
        decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon)),
      ),
    );
  }
}

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../core/app.dart';
import '../core/fx.dart';
import 'register_screen.dart';
import 'store_signup.dart';

String authError(Object e) {
  if (e is FirebaseAuthException) {
    switch (e.code) {
      case 'invalid-email':
        return 'الإيميل مكتوب غلط';
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        return 'الإيميل أو الباسورد غلط';
      case 'email-already-in-use':
        return 'الإيميل ده متسجل قبل كده — جرّب تسجيل الدخول';
      case 'weak-password':
        return 'الباسورد ضعيف — خليه 6 حروف أو أرقام على الأقل';
      case 'network-request-failed':
        return 'مفيش إنترنت';
      case 'too-many-requests':
        return 'محاولات كتير — استنى شوية وجرب تاني';
    }
    return e.message ?? e.code;
  }
  return e.toString();
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final email = TextEditingController();
  final pass = TextEditingController();
  bool busy = false;
  bool hide = true;

  Future<void> login() async {
    if (email.text.trim().isEmpty || pass.text.isEmpty) {
      toast(context, 'اكتب اسم المستخدم (أو الإيميل) والباسورد', error: true);
      return;
    }
    setState(() => busy = true);
    try {
      await auth.signInWithEmailAndPassword(
          email: loginToEmail(email.text), password: pass.text);
    } catch (e) {
      if (mounted) toast(context, authError(e), error: true);
    }
    if (mounted) setState(() => busy = false);
  }

  Future<void> forgot() async {
    if (email.text.trim().isEmpty) {
      toast(context, 'اكتب إيميلك الأول', error: true);
      return;
    }
    if (!email.text.contains('@')) {
      toast(context, 'لو نسيت كلمة السر كلّم إدارة SOL وهيبعتولك واحدة جديدة');
      return;
    }
    try {
      await auth.sendPasswordResetEmail(email: email.text.trim());
      if (mounted) toast(context, 'بعتنالك رسالة على الإيميل لتغيير الباسورد');
    } catch (e) {
      if (mounted) toast(context, authError(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(children: [
              FadeSlideIn(
                child: Floating(
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                            color: kAccent.withValues(alpha: 0.35),
                            blurRadius: 30,
                            offset: const Offset(0, 12)),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(24),
                      child: Image.asset('assets/logo.png', width: 180, height: 180),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              const Text('اطلب بضاعتك بسهولة',
                  style: TextStyle(fontSize: 16, color: Colors.black54)),
              const SizedBox(height: 28),
              TextField(
                controller: email,
                keyboardType: TextInputType.emailAddress,
                textDirection: TextDirection.ltr,
                decoration: const InputDecoration(
                    labelText: 'اسم المستخدم أو الإيميل', prefixIcon: Icon(Icons.person_outline)),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: pass,
                obscureText: hide,
                textDirection: TextDirection.ltr,
                decoration: InputDecoration(
                  labelText: 'الباسورد',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    icon: Icon(hide ? Icons.visibility : Icons.visibility_off),
                    onPressed: () => setState(() => hide = !hide),
                  ),
                ),
                onSubmitted: (_) => login(),
              ),
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: TextButton(onPressed: forgot, child: const Text('نسيت الباسورد؟')),
              ),
              const SizedBox(height: 6),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton(
                  onPressed: busy ? null : login,
                  child: busy
                      ? const SizedBox(
                          width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('دخول', style: TextStyle(fontSize: 16)),
                ),
              ),
              const SizedBox(height: 14),
              OutlinedButton.icon(
                onPressed: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const RegisterScreen())),
                icon: const Icon(Icons.storefront),
                label: const Text('عميل جديد؟ سجّل حسابك'),
              ),
              const SizedBox(height: 10),
              TextButton.icon(
                onPressed: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const StoreSignupScreen())),
                icon: const Icon(Icons.workspace_premium, color: kAccent),
                label: const Text('عندك محل؟ اشترك في البرنامج وشغّله باسمك'),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

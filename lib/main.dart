import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'admin/admin_home.dart';
import 'auth/login_screen.dart';
import 'auth/register_screen.dart';
import 'core/app.dart';
import 'core/migration.dart';
import 'customer/customer_home.dart';
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: solFirebaseOptions);
  runApp(const SolApp());
}

class SolApp extends StatelessWidget {
  const SolApp({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(
      seedColor: kPrimary,
      primary: kPrimary,
      secondary: kAccent,
    );
    return MaterialApp(
      title: 'SOL',
      debugShowCheckedModeBanner: false,
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData(
        colorScheme: scheme,
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF5F7FA),
        appBarTheme: const AppBarTheme(
          backgroundColor: kPrimary,
          foregroundColor: kAccent,
          centerTitle: true,
        ),
        cardTheme: CardThemeData(
          elevation: 0,
          color: Colors.white,
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: Colors.grey.shade200),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          filled: true,
          fillColor: Colors.white,
          isDense: true,
        ),
      ),
      home: const AuthGate(),
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: auth.authStateChanges(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Loading());
        }
        final user = snap.data;
        if (user == null) {
          Session.reset();
          return const LoginScreen();
        }
        if (isSuper) return const _SuperGate();
        return StreamBuilder(
          stream: db.collection('users').doc(user.uid).snapshots(),
          builder: (context, us) {
            if (us.hasError) return _ErrorScreen('${us.error}');
            if (!us.hasData) return const Scaffold(body: Loading());
            final me = us.data!.data();
            if (me == null) return const RegisterScreen(completeProfileOnly: true);
            final storeId = (me['storeId'] ?? kMainStore).toString();
            final role = (me['role'] ?? 'customer').toString();
            return _StoreGate(storeId: storeId, role: role);
          },
        );
      },
    );
  }
}

/// المدير العام: بينقل البيانات القديمة أول مرة، وبيقدر يدخل على أي محل
class _SuperGate extends StatefulWidget {
  const _SuperGate();
  @override
  State<_SuperGate> createState() => _SuperGateState();
}

class _SuperGateState extends State<_SuperGate> {
  late final Future<void> _migration = migrateToStores();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: _migration,
      builder: (context, m) {
        if (m.connectionState != ConnectionState.done) {
          return const Scaffold(
              body: Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
            CircularProgressIndicator(),
            SizedBox(height: 12),
            Text('بنجهّز البيانات...'),
          ])));
        }
        if (m.hasError) return _ErrorScreen('${m.error}');
        return ValueListenableBuilder<String>(
          valueListenable: Session.superStore,
          builder: (context, storeId, _) => _StoreGate(storeId: storeId, role: 'super'),
        );
      },
    );
  }
}

/// بيحمّل بيانات المحل (الاسم واللوجو والاشتراك) وبيفتح الشاشة المناسبة
class _StoreGate extends StatelessWidget {
  final String storeId;
  final String role;
  const _StoreGate({required this.storeId, required this.role});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: db.collection('stores').doc(storeId).snapshots(),
      builder: (context, ss) {
        if (ss.hasError) return _ErrorScreen('${ss.error}');
        if (!ss.hasData) return const Scaffold(body: Loading());
        final store = ss.data!.data();
        Session.storeId = storeId;
        Session.role = role;
        Session.store = store ?? {};
        if (role != 'super' && storeBlocked(store)) {
          return _BlockedScreen(store: store ?? {});
        }
        if (role == 'super' || role == 'owner') {
          return AdminHome(key: ValueKey('admin_$storeId'));
        }
        return CustomerHome(key: ValueKey('customer_$storeId'));
      },
    );
  }
}

class _BlockedScreen extends StatelessWidget {
  final Map<String, dynamic> store;
  const _BlockedScreen({required this.store});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              StoreLogo(size: 100, store: store),
              const SizedBox(height: 20),
              Text((store['name'] ?? '').toString(),
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              const Icon(Icons.lock_clock, size: 48, color: kDanger),
              const SizedBox(height: 8),
              Text(
                  Session.role == 'owner'
                      ? 'اشتراك المحل متوقف — كلّم إدارة SOL لتجديد الاشتراك'
                      : 'المحل ده مش متاح دلوقتي',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 16)),
              const SizedBox(height: 24),
              OutlinedButton.icon(
                onPressed: () => auth.signOut(),
                icon: const Icon(Icons.logout),
                label: const Text('تسجيل خروج'),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

class _ErrorScreen extends StatelessWidget {
  final String error;
  const _ErrorScreen(this.error);
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.error_outline, size: 48, color: kDanger),
              const SizedBox(height: 8),
              const Text('حصلت مشكلة في التحميل', style: TextStyle(fontSize: 17)),
              const SizedBox(height: 8),
              SelectableText(error,
                  textAlign: TextAlign.center, style: const TextStyle(color: Colors.black54)),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: () => auth.signOut(),
                icon: const Icon(Icons.logout),
                label: const Text('تسجيل خروج'),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:google_fonts/google_fonts.dart';

import 'notify.dart';
import 'screens/login.dart';
import 'screens/shell.dart';
import 'store.dart';
import 'ui.dart';

// نفس مشروع Firebase الذي يستعمله الموقع وتطبيقا الزبون والموصّل (dilivery-93064)
const firebaseOptions = FirebaseOptions(
  apiKey: 'AIzaSyAnAmGrt_gFF7-Y1ZVoq4I5PEaoaKjXbrg',
  appId: '1:248490849459:web:57c1746b9ce6c363bb6cc6',
  messagingSenderId: '248490849459',
  projectId: 'dilivery-93064',
  authDomain: 'dilivery-93064.firebaseapp.com',
  storageBucket: 'dilivery-93064.firebasestorage.app',
);

final messengerKey = GlobalKey<ScaffoldMessengerState>();
final navKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: firebaseOptions);
  app.onToast = (m) {
    final s = messengerKey.currentState;
    if (s == null) return;
    s.hideCurrentSnackBar();
    s.showSnackBar(SnackBar(content: Text(m), behavior: SnackBarBehavior.floating));
  };
  notify.onOpen = (_) {
    navKey.currentState?.popUntil((r) => r.isFirst);
    shopTab.value = 0; // تبويب الطلبات
  };
  await notify.init();
  await app.init();
  runApp(const ShopApp());
}

ThemeData buildTheme(Brightness b) {
  final dark = b == Brightness.dark;
  final scheme = ColorScheme.fromSeed(seedColor: brand, brightness: b).copyWith(
    primary: dark ? const Color(0xFF3DBB8C) : brand,
    secondary: orange,
    surface: dark ? const Color(0xFF161D26) : Colors.white,
  );
  final base = ThemeData(useMaterial3: true, colorScheme: scheme, brightness: b);
  final text = base.textTheme.apply(fontFamily: GoogleFonts.getFont('IBM Plex Sans Arabic').fontFamily);
  return base.copyWith(
    scaffoldBackgroundColor: dark ? const Color(0xFF0E131A) : const Color(0xFFF3F5F8),
    textTheme: text.copyWith(
      headlineSmall: GoogleFonts.getFont('Readex Pro', textStyle: text.headlineSmall, fontWeight: FontWeight.w600),
      titleLarge: GoogleFonts.getFont('Readex Pro', textStyle: text.titleLarge, fontWeight: FontWeight.w600),
      titleMedium: GoogleFonts.getFont('Readex Pro', textStyle: text.titleMedium, fontWeight: FontWeight.w600),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: scheme.outlineVariant)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: scheme.outlineVariant)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(54),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    snackBarTheme: SnackBarThemeData(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
  );
}

class ShopApp extends StatelessWidget {
  const ShopApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Delivery محل',
      debugShowCheckedModeBanner: false,
      scaffoldMessengerKey: messengerKey,
      navigatorKey: navKey,
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      home: ListenableBuilder(
        listenable: app,
        builder: (context, _) {
          if (!app.ready || app.role == 'resolving') {
            return const Scaffold(body: Center(child: CircularProgressIndicator()));
          }
          if (app.user == null) return const LoginScreen();
          if (app.role == 'shop') return const Shell();
          return const _Unlinked();
        },
      ),
    );
  }
}

class _Unlinked extends StatelessWidget {
  const _Unlinked();

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    return Scaffold(
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.all(24), children: [
          const SizedBox(height: 40),
          Icon(Icons.no_accounts_rounded, size: 64, color: Theme.of(context).hintColor),
          const SizedBox(height: 16),
          Text(app.role == 'error' ? 'تعذّر فتح حسابك' : 'هذا الحساب غير مرتبط بأي محل',
              textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(
            app.role == 'error'
                ? app.roleErr
                : 'هذا التطبيق لأصحاب المحلات فقط. اطلب من الإدارة ربط رقمك بمحلك، ثم ادخل برقمك وكلمة السر.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Theme.of(context).hintColor),
          ),
          const SizedBox(height: 20),
          Box(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('رمز الحساب (UID)', style: TextStyle(color: Theme.of(context).hintColor, fontSize: 12)),
              const SizedBox(height: 4),
              SelectableText(uid, textDirection: TextDirection.ltr),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: uid));
                  app.toast('نُسخ الرمز');
                },
                icon: const Icon(Icons.copy_rounded),
                label: const Text('نسخ الرمز'),
              ),
            ]),
          ),
          const SizedBox(height: 16),
          FilledButton(onPressed: app.logout, child: const Text('تسجيل الخروج')),
        ]),
      ),
    );
  }
}

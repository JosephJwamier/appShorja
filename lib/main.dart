import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'providers/auth_provider.dart';
import 'providers/items_provider.dart';
import 'providers/notifications_provider.dart';
import 'providers/chats_provider.dart';
import 'providers/category_provider.dart';
import 'providers/home_items_provider.dart';
import 'providers/following_provider.dart';
import 'providers/recommended_items_provider.dart';
import 'providers/recommended_listings_provider.dart';
import 'screens/login_screen.dart';
import 'providers/my_items_provider.dart';
import 'providers/auctions_provider.dart';
import 'providers/representative_requests_provider.dart';
import 'providers/store_provider.dart';
import 'providers/ledger_provider.dart';
import 'providers/live_sessions_provider.dart';
import 'providers/reels_provider.dart';
import 'providers/wallet_provider.dart';
import 'providers/transfers_provider.dart';
import 'providers/reservations_badge_provider.dart';
import 'features/location/providers/location_provider.dart';
import 'theme/app_colors.dart';
import 'screens/main_shell.dart';
import 'services/notification_service.dart';
import 'services/notification_navigator.dart';
import 'services/deep_link_service.dart';
import 'services/analytics_service.dart';
import 'screens/onboarding_screen.dart';
import 'widgets/legal/consent_gate.dart';
import 'firebase_options.dart';

final _notificationsProvider = NotificationsProvider();
// Singleton (not `create:`-provided) so the FCM foreground handler below —
// which runs before runApp() and has no BuildContext — can reach the exact
// same instance the widget tree uses, the same way _notificationsProvider
// already does.
final _chatsProvider = ChatsProvider();
final navigatorKey = GlobalKey<NavigatorState>();

/// Screen-view + custom event tracking. Safe to call on web/before Firebase
/// init too — the underlying plugin no-ops there.
final analytics = AppAnalytics.instance;

Future<void> main() async {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    if (!kIsWeb) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );

      // Crash reporting: don't pollute production crash data with reports
      // from local debug runs.
      await FirebaseCrashlytics.instance
          .setCrashlyticsCollectionEnabled(!kDebugMode);
      FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;
      PlatformDispatcher.instance.onError = (error, stack) {
        FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
        return true;
      };

      await NotificationService.initialize(
        onReceived: (title, body, type, data) {
          _notificationsProvider.addNotification(
            title: title,
            body: body,
            type: type,
            data: data,
          );
          // The badge on MainShell's "المحادثات" tab and the unread state
          // inside the list only reflected whatever was loaded at login or
          // the last manual refresh — a message arriving while the user was
          // elsewhere in the app never updated either. A push notification
          // is the only live signal available for that (there's no
          // app-wide inbox websocket, only per-open-thread ones).
          //
          // handleIncomingMessagePush patches the existing tile straight
          // from the push payload (no network call) when possible, only
          // falling back to a full refetch the first time a chat is seen.
          if (type == 'new_message') {
            _chatsProvider.handleIncomingMessagePush(data);
          }
        },
        onTap: (type, data) {
          final ctx = navigatorKey.currentContext;
          if (ctx != null) navigateForNotificationTap(ctx, type, data);
        },
      );
    }

    DeepLinkService.instance.init(navigatorKey);

    runApp(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => AuthProvider()),
          ChangeNotifierProvider(create: (_) => ItemsProvider()),
          ChangeNotifierProvider(create: (_) => MyItemsProvider()),
          ChangeNotifierProvider(create: (_) => AuctionsProvider()),
          ChangeNotifierProvider(
              create: (_) => RepresentativeRequestsProvider()),
          ChangeNotifierProvider(create: (_) => StoreProvider()),
          ChangeNotifierProvider(create: (_) => LedgerProvider()),
          ChangeNotifierProvider(create: (_) => LiveSessionsProvider()),
          ChangeNotifierProvider(create: (_) => ReelsProvider()),
          ChangeNotifierProvider(create: (_) => WalletProvider()),
          ChangeNotifierProvider(create: (_) => TransfersProvider()),
          ChangeNotifierProvider(create: (_) => ReservationsBadgeProvider()),
          ChangeNotifierProvider(create: (_) => LocationProvider()),
          ChangeNotifierProvider(create: (_) => CategoryProvider()),
          ChangeNotifierProvider(create: (_) => HomeItemsProvider()),
          ChangeNotifierProvider(create: (_) => FollowingProvider()),
          ChangeNotifierProvider(create: (_) => RecommendedItemsProvider()),
          ChangeNotifierProvider(create: (_) => RecommendedListingsProvider()),
          ChangeNotifierProvider.value(value: _chatsProvider),
          ChangeNotifierProvider.value(value: _notificationsProvider),
        ],
        child: const MyApp(),
      ),
    );
  }, (error, stack) {
    // Errors thrown outside the Flutter framework (e.g. in a bare async gap)
    // never reach FlutterError.onError — this zone is the catch-all for those.
    if (!kIsWeb) {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
    }
  });
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'الشورجة',
      debugShowCheckedModeBanner: false,
      // Firebase isn't initialized on web (see main()), so the observer
      // would crash trying to reach an app that was never set up.
      navigatorObservers: kIsWeb
          ? const []
          : [FirebaseAnalyticsObserver(analytics: analytics)],
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: AppColors.surface,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.primary,
          primary: AppColors.primary,
          onPrimary: AppColors.onPrimary,
          secondary: AppColors.secondary,
          tertiary: AppColors.tertiaryContainer,
          surface: AppColors.surface,
          onSurface: AppColors.onSurface,
          error: AppColors.error,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: AppColors.surface,
          foregroundColor: AppColors.primary,
          elevation: 0,
          centerTitle: true,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: AppColors.onPrimary,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ),
      home: const AuthGate(),
    );
  }
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

const _onboardingSeenKey = 'has_seen_onboarding';

class _AuthGateState extends State<AuthGate> {
  late final Future<void> _initFuture;
  bool _hasSeenOnboarding = false;

  @override
  void initState() {
    super.initState();
    _initFuture = _init();
  }

  Future<void> _init() async {
    // Resolve every provider before the first await: the gate can be
    // disposed while SharedPreferences is still loading (app backgrounded
    // during a cold start), and a BuildContext must not be read after that.
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final notifications =
        Provider.of<NotificationsProvider>(context, listen: false);
    final chats = Provider.of<ChatsProvider>(context, listen: false);

    final prefs = await SharedPreferences.getInstance();
    _hasSeenOnboarding = prefs.getBool(_onboardingSeenKey) ?? false;
    await auth.tryAutoLogin(
      notificationsProvider: notifications,
      chatsProvider: chats,
    );
  }

  Future<void> _completeOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_onboardingSeenKey, true);
    if (mounted) setState(() => _hasSeenOnboarding = true);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: _initFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        return Consumer<AuthProvider>(
          builder: (context, auth, _) {
            if (!auth.isLoggedIn) {
              // Shown once ever per install — introduces the app before the
              // very first login/signup, not shown again for returning users.
              if (!_hasSeenOnboarding) {
                return OnboardingScreen(onDone: _completeOnboarding);
              }
              return const LoginScreen();
            }

            final pendingType = NotificationService.pendingTapType;
            final pendingData = NotificationService.pendingTapData;
            if (pendingType != null && pendingData != null) {
              NotificationService.pendingTapType = null;
              NotificationService.pendingTapData = null;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                navigateForNotificationTap(context, pendingType, pendingData);
              });
            }
            // بوابة الموافقة: تُلزم المستخدم بالموافقة على أي شروط/سياسة
            // محدّثة قبل استخدام التطبيق (إعادة الموافقة عند التحديث).
            return ConsentGate(child: MainShell(key: mainShellKey));
          },
        );
      },
    );
  }
}

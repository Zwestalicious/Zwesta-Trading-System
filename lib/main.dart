// Zwesta Trading System — ML-Powered Trading Platform
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'screens/login_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/onboarding_screen.dart';
import 'services/auth_service.dart';
import 'services/trading_service.dart';
import 'services/bot_service.dart';
import 'services/statement_service.dart';
import 'services/financial_service.dart';
import 'services/ig_auto_connect_service.dart';
import 'services/commission_service.dart';
import 'services/broker_credentials_service.dart';
import 'services/vps_service.dart';
import 'services/risk_management_service.dart';
import 'services/trade_alert_service.dart';
import 'services/strategy_engine.dart';
import 'services/ml_status_service.dart';
import 'providers/currency_provider.dart';
import 'providers/fallback_status_provider.dart';
import 'theme/app_theme.dart';
import 'utils/environment_config.dart';
import 'l10n/app_localizations.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    // Set environment based on build mode
    // Both debug and release default to the VPS backend unless API_URL is
    // supplied via --dart-define. Local web routing is opt-in via
    // --dart-define=USE_LOCAL_WEB_API=true.
    if (kReleaseMode) {
      EnvironmentConfig.setEnvironment(Environment.production);
    } else {
      const String envMode = String.fromEnvironment('ZWESTA_ENV', defaultValue: 'staging');
      EnvironmentConfig.setEnvironment(
        envMode == 'development'
            ? Environment.development
            : Environment.staging,
      );
    }

    // The --dart-define=API_URL value (if supplied at build time) overrides
    // the default VPS backend at 197.184.101.190:9000. This is useful when the
    // backend is deployed to a remote VPS and the app runs on a different device.
    const String buildApiUrl = String.fromEnvironment('API_URL', defaultValue: '');
    if (buildApiUrl.isNotEmpty) {
      EnvironmentConfig.setApiUrl(buildApiUrl);
    }

    EnvironmentConfig.validateLaunchConfiguration();

    // Fail fast with a clear message instead of a cryptic "Future not completed"
    // if the backend cannot be reached.
    try {
      final Uri healthUri = Uri.parse('${EnvironmentConfig.apiUrl}/api/health');
      await http.get(healthUri).timeout(const Duration(seconds: 8));
    } catch (e) {
      runApp(MaterialApp(
        home: Scaffold(
          backgroundColor: Colors.red.shade50,
          body: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.cloud_off, color: Colors.red, size: 64),
                  const SizedBox(height: 16),
                  const Text(
                    'Cannot reach backend',
                    style: TextStyle(fontSize: 20, color: Colors.red, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Tried: ${EnvironmentConfig.apiUrl}/api/health\n$e',
                    style: const TextStyle(color: Colors.black87),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ));
      return;
    }

    runApp(const MyApp());
  } catch (e, st) {
    print('Main init error: $e\n$st');
    runApp(MaterialApp(
      home: Scaffold(
        backgroundColor: Colors.red.shade50,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, color: Colors.red, size: 64),
              SizedBox(height: 16),
              Text(
                'App failed to start',
                style: TextStyle(fontSize: 20, color: Colors.red, fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 8),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  e.toString(),
                  style: TextStyle(color: Colors.black87),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      ),
    ));
    }
  }

  class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    try {
      return MultiProvider(
        providers: [
          ChangeNotifierProvider(
            create: (_) => CurrencyProvider()..loadCurrency(),
          ),
          ChangeNotifierProvider(
            create: (_) => AuthService(),
          ),
          ChangeNotifierProvider(
            create: (_) => FallbackStatusProvider(),
          ),
          ChangeNotifierProxyProvider<AuthService, TradingService>(
            create: (context) => TradingService(null),
            update: (context, authService, tradingService) {
              tradingService?.updateToken(authService.token);
              return tradingService ?? TradingService(authService.token);
            },
          ),
          ChangeNotifierProvider(
            create: (_) => BotService(),
          ),
          ChangeNotifierProvider(
            create: (_) => StatementService(),
          ),
          ChangeNotifierProvider(
            create: (_) => FinancialService(),
          ),
          ChangeNotifierProvider(
            create: (_) => IGAutoConnectService()..autoConnect(),
          ),
          ChangeNotifierProvider(
            create: (_) => CommissionService(),
          ),
          ChangeNotifierProvider(
            create: (_) => BrokerCredentialsService(),
          ),
          ChangeNotifierProvider(
            create: (_) => VpsService(),
          ),
          ChangeNotifierProvider(
            create: (_) => RiskManagementService(),
          ),
          ChangeNotifierProvider(
            create: (_) => TradeAlertService(),
          ),
          ChangeNotifierProvider(
            create: (_) => StrategyEngine(),
          ),
          ChangeNotifierProvider(
            create: (_) => MLStatusService()..startPolling(),
          ),
        ],
        child: MaterialApp(
          title: 'ZWESTA TRADING SYSTEM',
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: ThemeMode.dark,
          home: const AuthWrapper(),
          debugShowCheckedModeBanner: false,
          supportedLocales: const [
            Locale('en'),
            Locale('xh'),
            Locale('zu'),
            Locale('nr'),
            Locale('ve'),
            Locale('af'),
          ],
          localizationsDelegates: [
            AppLocalizations.delegate,
            DefaultWidgetsLocalizations.delegate,
            DefaultMaterialLocalizations.delegate,
          ],
          localeResolutionCallback: (locale, supportedLocales) {
            if (locale == null) return supportedLocales.first;
            for (var supportedLocale in supportedLocales) {
              if (supportedLocale.languageCode == locale.languageCode) {
                return supportedLocale;
              }
            }
            return supportedLocales.first;
          },
        ),
      );
    } catch (e, st) {
      print('MyApp build error: $e\n$st');
      return MaterialApp(
        home: Scaffold(body: Center(child: Text('App error: $e'))),
      );
    }
  }
}

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({Key? key}) : super(key: key);

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  bool? _onboardingComplete;

  @override
  void initState() {
    super.initState();
    _checkOnboardingStatus();
  }

  Future<void> _checkOnboardingStatus() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _onboardingComplete = prefs.getBool('onboarding_complete') ?? false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    try {
      return Consumer<AuthService>(
        builder: (context, authService, _) {
          // Loading state while checking onboarding status
          if (_onboardingComplete == null) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }

          // If authenticated
          if (authService.isAuthenticated) {
            // Check if user needs to see onboarding
            if (!_onboardingComplete!) {
              return const OnboardingScreen();
            }
            return const DashboardScreen();
          }

          // Not authenticated - show login
          return const LoginScreen();
        },
      );
    } catch (e, st) {
      print('AuthWrapper build error: $e\n$st');
      return Scaffold(
        body: Center(child: Text('Auth error: $e')),
      );
    }
  }
}



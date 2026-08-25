import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/app_localizations.dart';
import '../models/trade.dart';
import '../providers/fallback_status_provider.dart';
import '../services/auth_service.dart';
import '../services/bot_service.dart';
import '../services/trading_service.dart';
import '../utils/environment_config.dart';
import '../theme/app_theme.dart';
import '../theme/app_design.dart';
import '../widgets/kill_switch_banner.dart';
import '../widgets/logo_widget.dart';
import 'account_management_screen.dart';
import 'admin_dashboard_screen.dart';
import 'admin_withdrawal_verification_screen.dart';
import 'binance_withdrawal_screen.dart';
import 'bot_configuration_route.dart';
import 'bot_dashboard_screen.dart';
import 'broker_analytics_dashboard.dart';
import 'broker_integration_screen.dart';
import 'commission_config_screen.dart';
import 'commission_dashboard_screen.dart';
import 'consolidated_reports_screen.dart';
import 'crypto_strategies_screen.dart';
import 'enhanced_dashboard_screen.dart';
import 'financials_screen.dart';
import 'binance_workspace_screen.dart';
import 'exness_workspace_screen.dart';
import 'fxcm_workspace_screen.dart';
import 'fxcm_withdrawal_screen.dart';
import 'multi_account_management_screen.dart';
import 'multi_broker_management_screen.dart';
import 'referral_dashboard_screen.dart';
import 'rentals_and_features_screen.dart';
import 'trade_analysis_screen.dart';
import 'trades_screen.dart';
import 'unified_broker_dashboard_screen.dart';
import 'user_wallet_screen.dart';
import 'activity_log_screen.dart';
import 'vps_management_screen.dart';

class _SampleCandle {
  final double time;
  final double close;
  _SampleCandle({required this.time, required this.close});
}

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({Key? key}) : super(key: key);

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> with SingleTickerProviderStateMixin {
  int _selectedIndex = 0;
  List<dynamic> _realBotsList = [];
  Timer? _refreshTimer;
  late final AnimationController _livePulse;
  int _refreshFailureCount = 0;
  int _consecutiveEmptyBotPayloads = 0;
  String _preferredBrokerDisplay = 'Exness';
  String _reportingCurrency = 'USD';

  static const Map<String, double> _currencyToZarRates = {
    'ZAR': 1.0,
    'USD': 18.5,
    'USDT': 18.5,
    'GBP': 24.0,
    'EUR': 20.0,
    'AUD': 12.0,
    'CAD': 13.5,
    'JPY': 0.12,
    'CHF': 20.5,
  };

  /// Convert currency code to symbol (e.g., ZAR → R, USD → $, EUR → €)
  String _currencySymbol(String code) {
    const symbols = {
      'USD': r'$', 'EUR': '€', 'GBP': '£', 'ZAR': 'R',
      'JPY': '¥', 'CHF': 'CHF', 'AUD': r'A$', 'CAD': r'C$',
      'NZD': r'NZ$', 'SGD': r'S$', 'HKD': r'HK$', 'CNY': '¥',
      'INR': '₹', 'BRL': r'R$', 'KRW': '₩', 'TRY': '₺',
      'MXN': r'MX$', 'PLN': 'zł', 'SEK': 'kr', 'NOK': 'kr',
      'NGN': '₦', 'KES': 'KSh', 'GHS': 'GH₵', 'USDT': 'USDT',
    };
    return symbols[code.toUpperCase()] ?? code;
  }

  String _normalizeCurrency(dynamic value) {
    final currency = value?.toString().trim().toUpperCase();
    return currency == null || currency.isEmpty ? 'USD' : currency;
  }

  String _formatCurrencyAmount(double amount, String currency, {int decimals = 2}) {
    return '${_currencySymbol(currency)}${amount.toStringAsFixed(decimals)}';
  }

  double _convertAmount(double amount, String sourceCurrency, [String? targetCurrency]) {
    final from = _normalizeCurrency(sourceCurrency);
    final to = _normalizeCurrency(targetCurrency ?? _reportingCurrency);
    if (from == to) {
      return amount;
    }

    final fromRate = _currencyToZarRates[from] ?? _currencyToZarRates['USD']!;
    final toRate = _currencyToZarRates[to] ?? _currencyToZarRates['USD']!;
    final amountInZar = amount * fromRate;
    return amountInZar / toRate;
  }

  String _formatReportedAmount(double amount, String sourceCurrency, {int decimals = 2}) {
    final target = _normalizeCurrency(_reportingCurrency);
    final converted = _convertAmount(amount, sourceCurrency, target);
    return _formatCurrencyAmount(converted, target, decimals: decimals);
  }

  String _truncateLabel(String value, {int maxLength = 64}) {
    final normalized = value.trim();
    if (normalized.length <= maxLength) {
      return normalized;
    }
    return '${normalized.substring(0, maxLength - 1)}…';
  }

  String? _scannerStrategySummary(Map<String, dynamic> bot) {
    final selection = bot['lastStrategySelection'];
    if (selection is! Map) return null;

    final strategy = selection['strategy']?.toString().trim();
    final bestSymbol = selection['bestSymbol']?.toString().trim();
    final bestSignal = selection['bestSignal']?.toString().trim();
    final hits = int.tryParse(selection['hits']?.toString() ?? '0') ?? 0;

    if (strategy == null || strategy.isEmpty) return null;

    final parts = <String>[strategy];
    if (bestSymbol != null && bestSymbol.isNotEmpty) {
      parts.add('on $bestSymbol');
    }
    if (bestSignal != null && bestSignal.isNotEmpty && bestSignal != 'NEUTRAL') {
      parts.add(bestSignal);
    }
    if (hits > 0) {
      parts.add('$hits setup${hits == 1 ? '' : 's'}');
    }
    return _truncateLabel(parts.join(' • '), maxLength: 72);
  }

  String? _lastStrategySwitchSummary(Map<String, dynamic> bot) {
    final event = bot['lastStrategyEvent'];
    if (event is! Map) return null;

    final fromStrategy = event['fromStrategy']?.toString().trim();
    final toStrategy = event['toStrategy']?.toString().trim();
    final reason = event['reason']?.toString().trim();

    if (toStrategy == null || toStrategy.isEmpty) return null;

    final summary = fromStrategy != null && fromStrategy.isNotEmpty
        ? '$fromStrategy -> $toStrategy'
        : toStrategy;
    if (reason == null || reason.isEmpty) {
      return _truncateLabel(summary, maxLength: 72);
    }

    return _truncateLabel('$summary • $reason', maxLength: 88);
  }

  String? _sizingSummary(Map<String, dynamic> bot) {
    final sizing = bot['lastSizingAdjustment'];
    if (sizing is! Map) return null;

    final state = sizing['state']?.toString().trim();
    final multiplier = double.tryParse(bot['effectivePositionSizeMultiplier']?.toString() ?? '') ??
        double.tryParse(sizing['multiplier']?.toString() ?? '') ??
        1.0;
    final reason = sizing['reason']?.toString().trim();

    if ((state == null || state.isEmpty) && (reason == null || reason.isEmpty) && multiplier == 1.0) {
      return null;
    }

    final parts = <String>[];
    if (state != null && state.isNotEmpty) {
      parts.add(state.toUpperCase());
    }
    parts.add('${multiplier.toStringAsFixed(2)}x size');
    if (reason != null && reason.isNotEmpty && reason != 'baseline sizing') {
      parts.add(reason);
    }
    return _truncateLabel(parts.join(' • '), maxLength: 92);
  }

  String? _pyramidSummary(Map<String, dynamic> bot) {
    final pyramidCount = int.tryParse(bot['pyramidOpenCount']?.toString() ?? '0') ?? 0;
    final opportunities = bot['scannerTopOpportunities'];
    String? topOpportunity;
    if (opportunities is List && opportunities.isNotEmpty && opportunities.first is Map) {
      final first = opportunities.first as Map;
      final symbol = first['symbol']?.toString().trim();
      final strength = double.tryParse(first['strength']?.toString() ?? '0') ?? 0.0;
      if (symbol != null && symbol.isNotEmpty) {
        topOpportunity = '$symbol ${strength.toStringAsFixed(0)}/100';
      }
    }

    if (pyramidCount <= 0 && topOpportunity == null) {
      return null;
    }

    final parts = <String>[];
    if (pyramidCount > 0) {
      parts.add('$pyramidCount add-on${pyramidCount == 1 ? '' : 's'} active');
    }
    if (topOpportunity != null) {
      parts.add('scanner lead $topOpportunity');
    }
    return _truncateLabel(parts.join(' • '), maxLength: 92);
  }

  String _accountCurrency(Map<String, dynamic> account) {
    return _normalizeCurrency(account['currency'] ?? account['account_currency']);
  }

  String _botCurrency(Map<String, dynamic> bot) {
    final rawCurrency = bot['displayCurrency'] ?? bot['accountCurrency'] ?? bot['currency'];
    return _normalizeCurrency(rawCurrency);
  }

  Map<String, double> _aggregateAccountBalances(
    Iterable<Map<String, dynamic>> accounts, {
    bool respectPortfolioTotalsFlag = false,
  }) {
    final totals = <String, double>{};
    for (final account in accounts) {
      if (respectPortfolioTotalsFlag && account['includeInPortfolioTotals'] == false) {
        continue;
      }
      final currency = _accountCurrency(account);
      final amount = (account['balance'] as num?)?.toDouble() ?? 0.0;
      totals[currency] = (totals[currency] ?? 0.0) + amount;
    }
    return totals;
  }

  List<Map<String, dynamic>> _connectedAccountsFor([String? mode]) {
    // Show all accounts that have data (connected or cached/offline), not only
    // actively-connected ones. This ensures all 3 Exness portals are visible
    // even when only 1 is actively connected via MT5.
    return _filteredBrokerAccounts(mode)
        .where((account) =>
            account['connected'] == true ||
            (account['accountNumber'] != null &&
             (account['accountNumber'] as String).isNotEmpty))
        .cast<Map<String, dynamic>>()
        .toList();
  }

  String _normalizedModeValue(dynamic value, {bool defaultLive = false}) {
    final normalized = value?.toString().trim().toLowerCase() ?? '';
    if (normalized == 'live' || normalized == 'real') return 'live';
    if (normalized == 'demo' || normalized == 'trial') return 'demo';
    return defaultLive ? 'live' : 'demo';
  }

  String _accountMode(Map<String, dynamic> account) {
    return _normalizedModeValue(
      account['mode'],
      defaultLive: account['is_live'] == true,
    );
  }

  String _botMode(Map<String, dynamic> bot) {
    return _normalizedModeValue(
      bot['mode'],
      defaultLive: bot['is_live'] == true,
    );
  }

  String _modeLabel(String mode) => mode == 'live' ? 'Live' : 'Demo';

  String _normalizeBrokerDisplayName(String broker) {
    final raw = broker.trim();
    if (raw.isEmpty) return '';
    final lower = raw.toLowerCase();
    if (lower == 'fxm') return 'FXCM';
    if (lower == 'prime xbt' || lower == 'pxbt') return 'PXBT';
    if (lower == 'binance') return 'Binance';
    if (lower == 'exness') return 'Exness';
    if (lower == 'ig markets' || lower == 'ig') return 'IG';
    return raw;
  }

  IconData _brokerIcon(String broker) {
    switch (_normalizeBrokerDisplayName(broker).toLowerCase()) {
      case 'exness':
        return Icons.show_chart;
      case 'fxcm':
        return Icons.currency_exchange;
      case 'binance':
        return Icons.diamond;
      case 'luno':
        return Icons.currency_bitcoin;
      case 'ig':
        return Icons.bar_chart;
      case 'pxbt':
        return Icons.bolt;
      default:
        return Icons.account_balance_wallet;
    }
  }

  Color _brokerAccentColor(String broker) {
    switch (_normalizeBrokerDisplayName(broker).toLowerCase()) {
      case 'exness':
        return const Color(0xFF00E5FF);
      case 'fxcm':
        return const Color(0xFF7C4DFF);
      case 'binance':
        return const Color(0xFFF0B90B);
      case 'luno':
        return const Color(0xFF03A9F4);
      case 'ig':
        return const Color(0xFFFF5252);
      case 'pxbt':
        return const Color(0xFFFF6D00);
      default:
        return const Color(0xFF00E5FF);
    }
  }

  String _formatAge(int seconds) {
    if (seconds < 60) return '${seconds}s';
    if (seconds < 3600) return '${seconds ~/ 60}m';
    if (seconds < 86400) return '${seconds ~/ 3600}h ${(seconds % 3600) ~/ 60}m';
    return '${seconds ~/ 86400}d';
  }

  Widget _buildDashboardSelectorPill({
    required String label,
    required bool selected,
    required VoidCallback onTap,
    EdgeInsetsGeometry padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
    double borderRadius = 14,
  }) {
    final backgroundColor = selected ? Theme.of(context).colorScheme.primary : const Color(0x1FFFFFFF);
    final borderColor = selected ? Colors.transparent : Colors.white.withOpacity(0.22);
    final textColor = selected ? Theme.of(context).colorScheme.onPrimary : Colors.white.withOpacity(0.92);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(borderRadius),
        child: Ink(
          padding: padding,
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(borderRadius),
            border: Border.all(color: borderColor, width: 1),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: Theme.of(context).colorScheme.primary.withOpacity(0.22),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.poppins(
              color: textColor,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }

  int _brokerDisplayPriority(String broker) {
    final normalized = _normalizeBrokerDisplayName(broker).toLowerCase();
    final preferred = _normalizeBrokerDisplayName(_preferredBrokerDisplay).toLowerCase();
    if (preferred.isNotEmpty && normalized == preferred) {
      return 0;
    }
    return 1;
  }

  List<Map<String, dynamic>> _sortedByPreferredBroker(Iterable<Map<String, dynamic>> accounts) {
    final sorted = accounts.toList();
    sorted.sort((a, b) {
      final brokerA = _normalizeBrokerDisplayName((a['broker'] ?? '').toString());
      final brokerB = _normalizeBrokerDisplayName((b['broker'] ?? '').toString());
      final priorityCompare = _brokerDisplayPriority(brokerA).compareTo(_brokerDisplayPriority(brokerB));
      if (priorityCompare != 0) {
        return priorityCompare;
      }
      return brokerA.toLowerCase().compareTo(brokerB.toLowerCase());
    });
    return sorted;
  }

  Color _modeAccent(String mode) {
    return mode == 'live'
        ? Theme.of(context).colorScheme.secondary
        : Theme.of(context).colorScheme.primary;
  }

  List<Map<String, dynamic>> _filteredBrokerAccounts([String? mode]) {
    final selectedMode = mode ?? _balanceMode;
    return _sortedByPreferredBroker(_brokerAccounts
        .where((account) => selectedMode == 'all' || _accountMode(account) == selectedMode)
        .cast<Map<String, dynamic>>()
      .toList());
  }

  List<Map<String, dynamic>> _applyPortfolioBrokerFilter(Iterable<Map<String, dynamic>> accounts) {
    final selectedBroker = _normalizeBrokerDisplayName(_portfolioBrokerFilter);
    if (selectedBroker.isEmpty || selectedBroker == 'All') {
      return accounts.cast<Map<String, dynamic>>().toList();
    }
    return accounts.where((account) {
      final broker = _normalizeBrokerDisplayName((account['broker'] ?? '').toString());
      return broker == selectedBroker;
    }).cast<Map<String, dynamic>>().toList();
  }

  List<Map<String, dynamic>> _filteredBots([String? mode]) {
    final selectedMode = mode ?? _balanceMode;
    return _realBotsList
        .where((bot) => selectedMode == 'all' || _botMode(Map<String, dynamic>.from(bot)) == selectedMode)
        .cast<Map<String, dynamic>>()
        .toList();
  }

  List<Map<String, dynamic>> _activeBotsFor([String? mode]) {
    return _filteredBots(mode)
        .where((bot) {
          if (bot['enabled'] == true) {
            return true;
          }
          final status = (bot['status'] ?? '').toString().trim().toUpperCase();
          return status == 'ACTIVE' || status == 'STARTING' || status == 'RUNNING';
        })
        .cast<Map<String, dynamic>>()
        .toList();
  }

  List<Map<String, dynamic>> _finishedBotsFor([String? mode]) {
    return _filteredBots(mode)
        .where((bot) {
          final enabled = bot['enabled'] == true;
          final status = (bot['status'] ?? '').toString().toUpperCase();
          return !enabled || status == 'STOPPED' || status == 'FINISHED' || status == 'COMPLETED';
        })
        .cast<Map<String, dynamic>>()
        .toList();
  }

  Map<String, double> _aggregateBotValuesFor(String field, {String? mode}) {
    final totals = <String, double>{};
    for (final bot in _filteredBots(mode)) {
      final currency = _botCurrency(bot);
      final amount = double.tryParse(bot[field]?.toString() ?? '0') ?? 0.0;
      totals[currency] = (totals[currency] ?? 0.0) + amount;
    }
    return totals;
  }

  String _preferredProfitCurrency([String? mode]) {
    final selectedBots = _filteredBots(mode);
    if (selectedBots.isNotEmpty) {
      return _botCurrency(selectedBots.first);
    }

    final selectedAccounts = _filteredBrokerAccounts(mode);
    if (selectedAccounts.isNotEmpty) {
      return _accountCurrency(selectedAccounts.first);
    }

    if (mode != null && mode != 'all') {
      return _preferredProfitCurrency();
    }

    return 'USD';
  }

  Widget _buildModeSummaryTile({
    required String mode,
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
  }) {
    final accent = _modeAccent(mode);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: accent.withOpacity(0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withOpacity(0.22)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: accent.withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: accent, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    value,
                    style: GoogleFonts.poppins(
                      color: accent,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: GoogleFonts.poppins(color: Colors.white54, fontSize: 10),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatCurrencyBreakdown(Map<String, double> totals, {int decimals = 2}) {
    final target = _normalizeCurrency(_reportingCurrency);
    if (totals.isEmpty) {
      return _formatCurrencyAmount(0, target, decimals: decimals);
    }
    if (totals.length == 1) {
      final entry = totals.entries.first;
      final currency = _normalizeCurrency(entry.key);
      return _formatCurrencyAmount(entry.value, currency, decimals: decimals);
    }
    final convertedTotal = totals.entries.fold<double>(
      0.0,
      (sum, entry) => sum + _convertAmount(entry.value, entry.key, target),
    );
    return _formatCurrencyAmount(convertedTotal, target, decimals: decimals);
  }

  // Broker account balances
  List<Map<String, dynamic>> _brokerAccounts = [];
  bool _brokerBalancesLoading = false;
  double _totalBrokerBalance = 0;

  // Demo/Live balance toggle
  String _balanceMode = 'all'; // 'all', 'live', 'demo'
  String _portfolioBrokerFilter = 'All';
  String? _botErrorMessage;

  // Balance tracking for increases/decreases
  // _sessionStartBalances is set ONCE on first fetch and never updated,
  // so balanceChange = currentBalance - sessionStart = total change this session.
  final Map<String, double> _sessionStartBalances = {};
  Map<String, double> _balanceChanges = {};

  // Withdrawal data
  List<Map<String, dynamic>> _recentWithdrawals = [];
  bool _withdrawalsLoading = false;
  bool _refreshInProgress = false;

  @override
  void initState() {
    super.initState();
    _livePulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true, period: const Duration(milliseconds: 1500));
    _loadPreferredBrokerDisplay();
    _runInitialDashboardLoads();
    // Delay auto refresh to avoid calling ModalRoute too early
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startAutoRefresh();
    });
  }

  void _runInitialDashboardLoads() {
    _loadCachedBots();
    _fetchRealBots();
    _fetchBrokerBalances();
    _fetchRecentWithdrawals();
  }

  Future<String> _dashboardBotsCacheKey() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = (prefs.getString('user_id') ?? '').trim();
    return userId.isEmpty ? 'dashboard_bots_snapshot' : 'dashboard_bots_snapshot_$userId';
  }

  Future<void> _loadCachedBots() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheKey = await _dashboardBotsCacheKey();
      final rawSnapshot = prefs.getString(cacheKey);
      if (rawSnapshot == null || rawSnapshot.trim().isEmpty) {
        return;
      }

      final decoded = jsonDecode(rawSnapshot);
      if (decoded is! List || decoded.isEmpty || !mounted) {
        return;
      }

      final cachedBots = List<Map<String, dynamic>>.from(decoded);
      setState(() {
        _realBotsList = cachedBots;
      });
    } catch (e) {
      print('⚠️ Failed to load cached dashboard bots: $e');
    }
  }

  Future<void> _persistCachedBots(List<Map<String, dynamic>> bots) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheKey = await _dashboardBotsCacheKey();
      if (bots.isEmpty) {
        await prefs.remove(cacheKey);
        return;
      }
      await prefs.setString(cacheKey, jsonEncode(bots));
    } catch (e) {
      print('⚠️ Failed to persist dashboard bots cache: $e');
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Any initialization that depends on inherited widgets goes here
  }

  Future<void> _loadPreferredBrokerDisplay() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = (prefs.getString('user_id') ?? '').trim();
    final scopedPreferredBrokerKey = userId.isEmpty ? 'preferred_broker_display' : 'preferred_broker_display_$userId';
    final scopedBrokerKey = userId.isEmpty ? 'broker' : 'broker_$userId';
    final selected = prefs.getString(scopedPreferredBrokerKey) ?? prefs.getString(scopedBrokerKey) ?? 'Exness';
    final savedReportingCurrency = _normalizeCurrency(prefs.getString('reporting_currency') ?? 'USD');
    final savedBalanceMode = (prefs.getString('dashboard_balance_mode') ?? 'all').trim().toLowerCase();
    final normalizedBalanceMode = {'all', 'live', 'demo'}.contains(savedBalanceMode) ? savedBalanceMode : 'all';
    if (!mounted) {
      return;
    }
    setState(() {
      _preferredBrokerDisplay = _normalizeBrokerDisplayName(selected);
      _portfolioBrokerFilter = 'All';
      _reportingCurrency = savedReportingCurrency == 'ZAR' ? 'ZAR' : 'USD';
      _balanceMode = normalizedBalanceMode;
    });
    _fetchBrokerBalances();
  }

  Future<void> _setBalanceMode(String mode) async {
    final normalizedMode = {'all', 'live', 'demo'}.contains(mode) ? mode : 'all';
    if (normalizedMode == _balanceMode) {
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final storedTradingMode = (prefs.getString('trading_mode') ?? '').trim().toUpperCase();
    final previousMode = storedTradingMode == 'LIVE' || storedTradingMode == 'DEMO'
        ? storedTradingMode
        : ((prefs.getBool('is_live_mode') ?? false) ? 'LIVE' : 'DEMO');
    final sessionToken = prefs.getString('auth_token');
    final userId = prefs.getString('user_id');

    await prefs.setString('dashboard_balance_mode', normalizedMode);
    if (!mounted) {
      return;
    }

    setState(() {
      _balanceMode = normalizedMode;
    });

    try {
      if (sessionToken == null || sessionToken.isEmpty || userId == null || userId.isEmpty) {
        throw Exception('Not authenticated');
      }

      final effectiveMode = normalizedMode == 'all' ? previousMode : normalizedMode.toUpperCase();
      if (normalizedMode != 'all') {
        final response = await http.post(
          Uri.parse('${EnvironmentConfig.apiUrl}/api/user/switch-mode'),
          headers: {
            'Content-Type': 'application/json',
            'X-Session-Token': sessionToken,
            'X-User-ID': userId,
          },
          body: jsonEncode({'mode': effectiveMode}),
        ).timeout(const Duration(seconds: 8));

        if (response.statusCode != 200) {
          throw Exception('Mode switch failed with HTTP ${response.statusCode}');
        }
        await prefs.setString('trading_mode', effectiveMode);
        await prefs.setBool('is_live_mode', effectiveMode == 'LIVE');
      }

      final botService = context.read<BotService>();
      botService.startPolling(tradingMode: effectiveMode);
      await botService.fetchActiveBots(tradingMode: effectiveMode, force: true);
      await _fetchBrokerBalances();
      await _fetchRealBots();
    } catch (e) {
      await prefs.setString('dashboard_balance_mode', previousMode == 'LIVE' ? 'live' : 'demo');
      await prefs.setString('trading_mode', previousMode);
      await prefs.setBool('is_live_mode', previousMode == 'LIVE');
      if (!mounted) {
        return;
      }
      setState(() {
        _balanceMode = previousMode == 'LIVE' ? 'live' : 'demo';
      });
      rethrow;
    }
  }

  Future<Map<String, dynamic>?> _loadLocalBrokerSnapshot() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = (prefs.getString('user_id') ?? '').trim();
    final scopedSnapshotKey = userId.isEmpty ? 'verified_broker_snapshot' : 'verified_broker_snapshot_$userId';
    final scopedConnectedKey = userId.isEmpty ? 'broker_connected' : 'broker_connected_$userId';
    final scopedPreferredBrokerKey = userId.isEmpty ? 'preferred_broker_display' : 'preferred_broker_display_$userId';
    final scopedBrokerNameKey = userId.isEmpty ? 'broker_name' : 'broker_name_$userId';
    final scopedBrokerKey = userId.isEmpty ? 'broker' : 'broker_$userId';
    final scopedFxcmAccountKey = userId.isEmpty ? 'fxcm_account_number' : 'fxcm_account_number_$userId';
    final scopedAccountKey = userId.isEmpty ? 'account_number' : 'account_number_$userId';
    final scopedMt5AccountKey = userId.isEmpty ? 'mt5_account' : 'mt5_account_$userId';
    final scopedIsLiveModeKey = userId.isEmpty ? 'is_live_mode' : 'is_live_mode_$userId';
    final scopedBalanceKey = userId.isEmpty ? 'account_balance' : 'account_balance_$userId';
    final scopedEquityKey = userId.isEmpty ? 'account_equity' : 'account_equity_$userId';
    final scopedFreeMarginKey = userId.isEmpty ? 'account_free_margin' : 'account_free_margin_$userId';
    final scopedMarginKey = userId.isEmpty ? 'account_margin' : 'account_margin_$userId';
    final scopedMarginLevelKey = userId.isEmpty ? 'account_margin_level' : 'account_margin_level_$userId';
    final scopedProfitKey = userId.isEmpty ? 'account_profit' : 'account_profit_$userId';
    final scopedCurrencyKey = userId.isEmpty ? 'account_currency' : 'account_currency_$userId';
    final scopedConnectionTimeKey = userId.isEmpty ? 'connection_time' : 'connection_time_$userId';

    final rawSnapshot = prefs.getString(scopedSnapshotKey);
    if (rawSnapshot != null && rawSnapshot.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(rawSnapshot);
        if (decoded is Map<String, dynamic> && decoded['connected'] == true) {
          return decoded;
        }
      } catch (_) {}
    }

    final isConnected = prefs.getBool(scopedConnectedKey) == true;
    if (!isConnected) {
      return null;
    }

    final broker = _normalizeBrokerDisplayName(
      prefs.getString(scopedPreferredBrokerKey) ??
          prefs.getString(scopedBrokerNameKey) ??
          prefs.getString(scopedBrokerKey) ??
          '',
    );
    final fallbackAccount = broker.toLowerCase() == 'fxcm'
        ? (prefs.getString(scopedFxcmAccountKey) ?? '')
        : (prefs.getString(scopedAccountKey) ?? prefs.getString(scopedMt5AccountKey) ?? '');
    final accountNumber = fallbackAccount.trim();
    if (broker.isEmpty || accountNumber.isEmpty) {
      return null;
    }

    final isLive = prefs.getBool(scopedIsLiveModeKey) == true;
    final balance = prefs.getDouble(scopedBalanceKey) ?? 0.0;
    final equity = prefs.getDouble(scopedEquityKey) ?? balance;
    final freeMargin = prefs.getDouble(scopedFreeMarginKey) ?? 0.0;
    final margin = prefs.getDouble(scopedMarginKey) ?? 0.0;
    final marginLevel = prefs.getDouble(scopedMarginLevelKey) ?? 0.0;
    final profit = prefs.getDouble(scopedProfitKey) ?? 0.0;
    final currency = _normalizeCurrency(prefs.getString(scopedCurrencyKey) ?? 'USD');
    final lastUpdate = prefs.getString(scopedConnectionTimeKey);

    return {
      'broker': broker,
      'accountNumber': accountNumber,
      'balance': balance,
      'equity': equity,
      'marginFree': freeMargin,
      'margin': margin,
      'margin_level': marginLevel,
      'total_pl': profit,
      'currency': currency,
      'displayCurrency': currency,
      'connected': true,
      'mode': isLive ? 'Live' : 'Demo',
      'is_live': isLive,
      'dataSource': 'local_snapshot',
      'last_update': lastUpdate,
      'warning': 'Showing the most recent verified broker snapshot from this device.',
    };
  }

  List<Map<String, dynamic>> _mergeLocalSnapshotIntoAccounts(
    List<Map<String, dynamic>> accounts,
    Map<String, dynamic>? localSnapshot,
  ) {
    if (localSnapshot == null) {
      return accounts;
    }

    final merged = List<Map<String, dynamic>>.from(accounts);
    final snapshotBroker = _normalizeBrokerDisplayName((localSnapshot['broker'] ?? '').toString());
    final snapshotAccount = (localSnapshot['accountNumber'] ?? '').toString().trim();
    final snapshotMode = _normalizedModeValue(
      localSnapshot['mode'],
      defaultLive: localSnapshot['is_live'] == true,
    );

    final existingIndex = merged.indexWhere((account) {
      final broker = _normalizeBrokerDisplayName((account['broker'] ?? '').toString());
      final accountNumber = (account['accountNumber'] ?? '').toString().trim();
      final mode = _normalizedModeValue(
        account['mode'],
        defaultLive: account['is_live'] == true,
      );
      return broker == snapshotBroker && accountNumber == snapshotAccount && mode == snapshotMode;
    });

    if (existingIndex >= 0) {
      final existing = Map<String, dynamic>.from(merged[existingIndex]);
      final existingConnected = existing['connected'] == true;
      final existingBalance = (existing['balance'] as num?)?.toDouble() ?? 0.0;
      if (!existingConnected || existingBalance <= 0) {
        merged[existingIndex] = {
          ...localSnapshot,
          ...existing,
          'connected': true,
          'balance': existingBalance > 0 ? existing['balance'] : localSnapshot['balance'],
          'equity': ((existing['equity'] as num?)?.toDouble() ?? 0.0) > 0 ? existing['equity'] : localSnapshot['equity'],
          'marginFree': ((existing['marginFree'] as num?)?.toDouble() ?? 0.0) > 0 ? existing['marginFree'] : localSnapshot['marginFree'],
          'margin': existing['margin'] ?? localSnapshot['margin'],
          'margin_level': existing['margin_level'] ?? localSnapshot['margin_level'],
          'total_pl': existing['total_pl'] ?? localSnapshot['total_pl'],
          'currency': existing['currency'] ?? localSnapshot['currency'],
          'displayCurrency': existing['displayCurrency'] ?? localSnapshot['displayCurrency'],
          'dataSource': existing['dataSource'] == 'live' ? 'live' : localSnapshot['dataSource'],
          'warning': existing['warning'] ?? localSnapshot['warning'],
        };
      }
      return merged;
    }

    merged.add(Map<String, dynamic>.from(localSnapshot));
    return merged;
  }

  Future<void> _setReportingCurrency(String currency) async {
    final normalized = _normalizeCurrency(currency) == 'ZAR' ? 'ZAR' : 'USD';
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('reporting_currency', normalized);
    if (!mounted) {
      return;
    }
    setState(() {
      _reportingCurrency = normalized;
    });
  }

  @override
  void dispose() {
    _livePulse.dispose();
    _refreshTimer?.cancel();
    super.dispose();
  }

  bool _isDashboardRouteActive() {
    try {
      final route = ModalRoute.of(context);
      return route == null || route.isCurrent;
    } catch (e) {
      // If context is not available yet, assume it's active
      return true;
    }
  }

  /// Fetch broker account balances from /api/accounts/balances
  Future<void> _fetchBrokerBalances() async {
    if (_brokerBalancesLoading) return;
    setState(() => _brokerBalancesLoading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final localSnapshot = await _loadLocalBrokerSnapshot();
      final sessionToken = prefs.getString('auth_token');
      if (sessionToken == null || sessionToken.isEmpty) {
        throw Exception('No auth token');
      }

      final modeParam = _balanceMode == 'all' ? 'ALL' : _balanceMode.toUpperCase();
      final response = await http.get(
        Uri.parse('${EnvironmentConfig.apiUrl}/api/accounts/balances?mode=$modeParam'),
        headers: {
          'Content-Type': 'application/json',
          'X-Session-Token': sessionToken,
        },
      ).timeout(const Duration(seconds: 20)); // Increased timeout to allow broker connections

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && mounted) {
          final mergedAccounts = _mergeLocalSnapshotIntoAccounts(
            List<Map<String, dynamic>>.from(data['accounts'] ?? []),
            localSnapshot,
          );
          // Calculate balance changes vs session start (set once, never overwritten)
          final newChanges = <String, double>{};
          for (final account in mergedAccounts) {
            final key = '${account['broker']}_${account['accountNumber']}';
            final currentBalance = (account['balance'] as num?)?.toDouble() ?? 0;
            // Only record the starting balance the very first time we see this account
            _sessionStartBalances[key] ??= currentBalance;
            newChanges[key] = currentBalance - _sessionStartBalances[key]!;
          }
          
          setState(() {
            _brokerAccounts = mergedAccounts;
            _totalBrokerBalance = mergedAccounts.fold<double>(
              0.0,
              (sum, account) => sum + ((account['balance'] as num?)?.toDouble() ?? 0.0),
            );
            _balanceChanges = newChanges;
          });
        }
      } else {
        throw Exception('API returned ${response.statusCode}');
      }
    } catch (e) {
      print('DEBUG: Broker balance fetch error: $e');
      final localSnapshot = await _loadLocalBrokerSnapshot();
      if (mounted && localSnapshot != null) {
        setState(() {
          _brokerAccounts = _mergeLocalSnapshotIntoAccounts([], localSnapshot);
          _totalBrokerBalance = (localSnapshot['balance'] as num?)?.toDouble() ?? 0.0;
        });
      }
    } finally {
      if (mounted) setState(() => _brokerBalancesLoading = false);
    }
  }

  /// Fetch recent withdrawals
  Future<void> _fetchRecentWithdrawals() async {
    if (_withdrawalsLoading) return;
    setState(() => _withdrawalsLoading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final sessionToken = prefs.getString('auth_token');
      if (sessionToken == null || sessionToken.isEmpty) {
        throw Exception('No auth token');
      }

      final response = await http.get(
        Uri.parse('${EnvironmentConfig.apiUrl}/api/withdrawals/recent'),
        headers: {
          'Content-Type': 'application/json',
          'X-Session-Token': sessionToken,
        },
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && mounted) {
          setState(() {
            _recentWithdrawals = List<Map<String, dynamic>>.from(data['withdrawals'] ?? []);
          });
        }
      } else {
        throw Exception('API returned ${response.statusCode}');
      }
    } catch (e) {
      print('DEBUG: Withdrawal fetch error: $e');
    } finally {
      if (mounted) setState(() => _withdrawalsLoading = false);
    }
  }

  /// Fetch all bots so dashboard can separate live/demo locally.
  Future<void> _fetchRealBots() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final sessionToken = prefs.getString('auth_token');
      final userId = prefs.getString('user_id');
      print('[DEBUG] _fetchRealBots: sessionToken present=${sessionToken != null && sessionToken.isNotEmpty}, userId=$userId');
      final previousBots = List<Map<String, dynamic>>.from(
        _realBotsList.whereType<Map<String, dynamic>>(),
      );
      if (sessionToken == null || sessionToken.isEmpty) {
        throw Exception('Session token missing. Please login again.');
      }

      final modeParam = _balanceMode == 'all' ? 'ALL' : _balanceMode.toUpperCase();
      var url = '${EnvironmentConfig.apiUrl}/api/bot/summary?mode=$modeParam&include_history=true&include_broker_snapshots=true';
      if (userId != null && userId.isNotEmpty) {
        url += '&user_id=$userId';
      }
      print('[DEBUG] _fetchRealBots: fetching from $url');

      final response = await http.get(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'X-Session-Token': sessionToken,
        },
      ).timeout(const Duration(seconds: 15));

      print('[DEBUG] _fetchRealBots: response status=${response.statusCode}, bodyLen=${response.body.length}');
      if (response.statusCode != 200) {
        print('[DEBUG] _fetchRealBots: non-200 body: ${response.body.substring(0, response.body.length > 200 ? 200 : response.body.length)}');
        throw Exception('API returned ${response.statusCode}');
      }

      final data = jsonDecode(response.body);
      if (data['success'] != true) {
        throw Exception(data['error'] ?? 'Failed to load bots');
      }

      final fetchedBots = List<Map<String, dynamic>>.from(data['bots'] ?? []);
      if (fetchedBots.isEmpty && previousBots.isNotEmpty) {
        _consecutiveEmptyBotPayloads += 1;
        if (_consecutiveEmptyBotPayloads < 2) {
          print('⚠️ Ignoring transient empty bot payload during refresh');
          return;
        }
      } else {
        _consecutiveEmptyBotPayloads = 0;
      }

      if (mounted) {
        setState(() {
          _realBotsList = fetchedBots;
        });
      }
      await _persistCachedBots(fetchedBots);
    } catch (e, st) {
      // Don't wipe existing bot data on refresh errors - preserve previous data
      print('[DEBUG] Bot refresh error (keeping previous data): $e');
      print('[DEBUG] Bot refresh stack trace: $st');
      // Surface the error so the user can see what went wrong
      if (mounted) {
        setState(() {
          _botErrorMessage = 'Failed to load bots: $e';
        });
      }
    }
  }

  void _startAutoRefresh() {
    _refreshTimer?.cancel();
    _refreshFailureCount = 0;

    // Initial refresh - delay slightly to ensure widget is fully built
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) {
        _performRefresh();
      }
    });

    // Subsequent refreshes with exponential backoff on error
    _refreshTimer = Timer.periodic(const Duration(seconds: 15), (timer) {
      if (mounted && _isDashboardRouteActive()) {
        _performRefresh();
      }
    });
  }
  
  Future<void> _performRefresh() async {
    if (_refreshInProgress || !_isDashboardRouteActive()) return;
    _refreshInProgress = true;
    try {
      await _fetchRealBots();
      await _fetchBrokerBalances();
      await _fetchRecentWithdrawals();
      
      if (mounted) {
        setState(() {
          _refreshFailureCount = 0; // Reset on success
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _refreshFailureCount++;
        });
      }
    } finally {
      _refreshInProgress = false;
    }
  }

  Future<void> _pushScreen(Widget screen) async {
    final result = await Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
    if (!mounted) {
      return;
    }
    if (screen is BotConfigurationRoute && result == true) {
      await _loadPreferredBrokerDisplay();
      await _performRefresh();
    }
  }

  void _openFinancials() {
    final tradingService = context.read<TradingService>();
    if (tradingService.primaryAccount != null) {
      _pushScreen(FinancialsScreen(account: tradingService.primaryAccount!));
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('No account available for financial reports')),
    );
  }

  void _openReferralDashboard() {
    final userId = context.read<AuthService>().currentUser?.id ?? '0';
    _pushScreen(ReferralDashboardScreen(userId: userId));
  }

  /// Get the current screen based on selected index
  Widget _getScreenForIndex(int index) {
    switch (index) {
      case 0:
        return _buildDashboardTab();
      case 1:
        return const TradesScreen();
      case 2:
        return const AccountManagementScreen();
      case 3:
        return const BotDashboardScreen(embedded: true);
      case 4:
        return _buildFeatureHubTab();
      default:
        return _buildDashboardTab();
    }
  }

  // ────── HELPER METHODS ──────

  /// Build the connected broker account card showing balance and withdrawals
  Widget _buildConnectedBrokerCard() {
    final allConnectedAccounts = _connectedAccountsFor();

    if (allConnectedAccounts.isEmpty) {
      return const SizedBox.shrink();
    }

    final brokerOptions = <String>{'All'};
    // Add brokers from ALL accounts (not just connected), so FXCM always appears
    for (final account in _brokerAccounts) {
      final broker = _normalizeBrokerDisplayName((account['broker'] ?? '').toString());
      if (broker.isNotEmpty) {
        brokerOptions.add(broker);
      }
    }

    final preferredFromSelection = _normalizeBrokerDisplayName(_portfolioBrokerFilter);
    final selectedBrokerFilter = brokerOptions.contains(preferredFromSelection)
      ? preferredFromSelection
      : 'All';

    final selectedAccounts = selectedBrokerFilter == 'All'
        ? _applyPortfolioBrokerFilter(_filteredBrokerAccounts())
        : _filteredBrokerAccounts()
        .where((account) => _normalizeBrokerDisplayName((account['broker'] ?? '').toString()).toLowerCase() == selectedBrokerFilter.toLowerCase())
            .toList();

    final selectedBalanceBreakdown = _aggregateAccountBalances(selectedAccounts);
    final selectedCurrency = selectedAccounts.isNotEmpty
      ? _accountCurrency(selectedAccounts.first)
      : _reportingCurrency;

    final selectedWithdrawals = _recentWithdrawals.where((withdrawal) {
      if (selectedBrokerFilter == 'All') {
        return true;
      }
      final withdrawalBroker = (withdrawal['broker'] ?? '').toString().trim().toLowerCase();
      return withdrawalBroker == selectedBrokerFilter.toLowerCase();
    }).toList();
    final selectedWithdrawnTotal = selectedWithdrawals.fold<double>(
      0.0,
      (sum, withdrawal) => sum + ((withdrawal['amount'] as num?)?.toDouble() ?? 0.0),
    );

    final sortedBrokers = brokerOptions.toList()
      ..sort((a, b) {
        if (a == 'All') return -1;
        if (b == 'All') return 1;
        final priorityCompare = _brokerDisplayPriority(a).compareTo(_brokerDisplayPriority(b));
        if (priorityCompare != 0) {
          return priorityCompare;
        }
        return a.compareTo(b);
      });

    final brokerFilterChips = sortedBrokers
        .map((broker) => _buildDashboardSelectorPill(
              label: broker,
              selected: selectedBrokerFilter == broker,
              onTap: () {
                setState(() {
                  _portfolioBrokerFilter = _normalizeBrokerDisplayName(broker);
                });
              },
            ))
        .toList();

    return Column(
      children: [
        _glassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Broker Portfolio Navigator',
                style: GoogleFonts.poppins(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: brokerFilterChips,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _buildMetricCard(
                      'Portfolio Balance',
                      _formatCurrencyBreakdown(selectedBalanceBreakdown),
                      Colors.white,
                      Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildMetricCard(
                      'Withdrawals',
                      _formatReportedAmount(selectedWithdrawnTotal, selectedCurrency),
                      Colors.white,
                      Theme.of(context).colorScheme.secondary,
                    ),
                  ),
                ],
              ),
            ],
          ),
                    ),
                    const SizedBox(height: 12),
        if (selectedAccounts.isEmpty)
          _glassCard(
            child: Text(
              'No connected accounts under ${selectedBrokerFilter.toUpperCase()}.',
              style: GoogleFonts.poppins(color: Colors.white70, fontSize: 13),
            ),
          ),
        ...selectedAccounts.asMap().entries.map((entry) {
          final connected = entry.value;
          final broker = connected['broker'] ?? 'Broker';
          final accountId = connected['accountId']?.toString() ?? '';
          final accountNum = connected['accountNumber']?.toString() ?? accountId;
          final balance = (connected['balance'] as num?)?.toDouble() ?? 0.0;
          final equity = (connected['equity'] as num?)?.toDouble() ?? 0.0;
          final currency = connected['currency'] ?? 'USD';
          final mode = _accountMode(connected);
          final key = '${broker}_$accountNum';
          final balanceChange = _balanceChanges[key] ?? 0.0;
          final isIncreasing = balanceChange >= 0;
          final accountWithdrawals = _recentWithdrawals
              .where((w) {
                final sameBroker = (w['broker']?.toString() ?? '').trim().toLowerCase() == broker.toString().trim().toLowerCase();
                if (!sameBroker) {
                  return false;
                }
                final withdrawalAccount = (w['accountNumber']?.toString() ?? '').trim();
                if (withdrawalAccount.isEmpty) {
                  return true;
                }
                return withdrawalAccount == accountNum;
              })
              .toList();
          final totalWithdrawn = accountWithdrawals.fold<double>(
            0,
            (sum, withdrawal) => sum + ((withdrawal['amount'] as num?)?.toDouble() ?? 0),
          );
          final dataSource = (connected['dataSource'] ?? '').toString();
          final isStale = dataSource == 'stale_cache';
          final isNotConnected = dataSource == 'not_connected';
          final cacheAgeSeconds = (connected['cacheAgeSeconds'] as num?)?.toInt();
          final warningMsg = (connected['warning'] ?? '').toString();
          final lastKnownBalance = (connected['lastKnownBalance'] as num?)?.toDouble();
          final lastKnownCurrency = (connected['lastKnownCurrency'] ?? currency).toString();
          return Padding(
            padding: EdgeInsets.only(bottom: entry.key == selectedAccounts.length - 1 ? 0 : 16),
            child: _glassCard(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  if (isIncreasing)
                    context.semantic.profit.withValues(alpha: 0.3)
                  else
                    context.semantic.loss.withValues(alpha: 0.3),
                  Colors.transparent,
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: _brokerAccentColor(broker.toString()).withOpacity(0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(_brokerIcon(broker.toString()), color: _brokerAccentColor(broker.toString()), size: 28),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    isStale ? '$broker (Stale)' : isNotConnected ? '$broker (Offline)' : 'Connected to $broker',
                                    style: GoogleFonts.poppins(
                                      color: isStale ? Theme.of(context).colorScheme.secondary : isNotConnected ? Colors.white38 : Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                if (isStale) ...[
                                  const SizedBox(width: 6),
                                  const Icon(Icons.warning_amber_rounded, color: Color(0xFFFFB74D), size: 18),
                                ],
                              ],
                            ),
                            Text(
                              'Account #$accountNum',
                              style: GoogleFonts.poppins(
                                color: Colors.white60,
                                fontSize: 12,
                              ),
                            ),
                            if (_normalizeBrokerDisplayName(broker.toString()).toLowerCase() == 'fxcm') ...[
                              const SizedBox(height: 8),
                              InkWell(
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(builder: (_) => const FxcmWorkspaceScreen()),
                                  );
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF00E5FF).withOpacity(0.14),
                                    borderRadius: BorderRadius.circular(999),
                                    border: Border.all(color: const Color(0xFF00E5FF).withOpacity(0.45)),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.space_dashboard_outlined, color: Color(0xFF00E5FF), size: 14),
                                      const SizedBox(width: 6),
                                      Text(
                                        'Open FXCM Workspace',
                                        style: GoogleFonts.poppins(
                                          color: const Color(0xFF00E5FF),
                                          fontSize: 10,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                            if (_normalizeBrokerDisplayName(broker.toString()).toLowerCase() == 'binance') ...[
                              const SizedBox(height: 8),
                              InkWell(
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(builder: (_) => const BinanceWorkspaceScreen()),
                                  );
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF3BA2F).withOpacity(0.14),
                                    borderRadius: BorderRadius.circular(999),
                                    border: Border.all(color: const Color(0xFFF3BA2F).withOpacity(0.45)),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.candlestick_chart, color: Color(0xFFF3BA2F), size: 14),
                                      const SizedBox(width: 6),
                                      Text(
                                        'Open Binance Workspace',
                                        style: GoogleFonts.poppins(
                                          color: const Color(0xFFF3BA2F),
                                          fontSize: 10,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                            if (_normalizeBrokerDisplayName(broker.toString()).toLowerCase() == 'exness') ...[
                              const SizedBox(height: 8),
                              InkWell(
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => ExnessWorkspaceScreen(
                                        accountData: Map<String, dynamic>.from(connected),
                                        balanceChange: balanceChange,
                                        totalWithdrawn: totalWithdrawn,
                                      ),
                                    ),
                                  );
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF00E676).withOpacity(0.14),
                                    borderRadius: BorderRadius.circular(999),
                                    border: Border.all(color: const Color(0xFF00E676).withOpacity(0.45)),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.monitor_heart_outlined, color: Color(0xFF00E676), size: 14),
                                      const SizedBox(width: 6),
                                      Text(
                                        'Open Exness Workspace',
                                        style: GoogleFonts.poppins(
                                          color: const Color(0xFF00E676),
                                          fontSize: 10,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: _modeAccent(mode).withOpacity(0.15),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          _modeLabel(mode),
                          style: GoogleFonts.poppins(
                            color: _modeAccent(mode),
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  // ── Staleness / Cache Warning Banner ──
                  if (isStale || isNotConnected || warningMsg.isNotEmpty) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: (isStale ? const Color(0xFFFFB74D) : const Color(0xFF78909C)).withOpacity(0.12),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: (isStale ? const Color(0xFFFFB74D) : const Color(0xFF78909C)).withOpacity(0.3),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            isStale ? Icons.access_time : Icons.cloud_off,
                            color: isStale ? const Color(0xFFFFB74D) : const Color(0xFF78909C),
                            size: 16,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  isStale
                                      ? 'Stale data${cacheAgeSeconds != null ? ' (${_formatAge(cacheAgeSeconds)} old)' : ''}'
                                      : 'Not connected',
                                  style: GoogleFonts.poppins(
                                    color: isStale ? const Color(0xFFFFB74D) : const Color(0xFF78909C),
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                if (isStale && lastKnownBalance != null && lastKnownBalance > 0)
                                  Text(
                                    'Last known: ${_formatCurrencyAmount(lastKnownBalance, lastKnownCurrency)}',
                                    style: GoogleFonts.poppins(color: Colors.white38, fontSize: 10),
                                  ),
                                if (warningMsg.isNotEmpty)
                                  Text(
                                    warningMsg,
                                    style: GoogleFonts.poppins(color: Colors.white38, fontSize: 10),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  // Grid of account metrics (2x3)
                  GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    childAspectRatio: 1.4,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    children: [
                      _buildMetricCard('Balance', _formatReportedAmount(balance, currency), Colors.white, const Color(0xFF00E5FF)),
                      _buildMetricCard('Equity', _formatReportedAmount(equity, currency), Colors.white, const Color(0xFF4CAF50)),
                      _buildMetricCard(
                        'Free Margin',
                        _formatReportedAmount(((connected['free_margin'] as num?)?.toDouble() ?? 0.0), currency),
                        Colors.white,
                        const Color(0xFF81C784),
                      ),
                      _buildMetricCard(
                        'Margin Used',
                        _formatReportedAmount(((connected['margin'] as num?)?.toDouble() ?? 0.0), currency),
                        Colors.white,
                        const Color(0xFFFFB74D),
                      ),
                      _buildMetricCard(
                        'Margin Level',
                        '${((connected['margin_level'] as num?)?.toDouble() ?? 0.0).toStringAsFixed(2)}%',
                        Colors.white,
                        const Color(0xFF64B5F6),
                      ),
                      _buildMetricCard(
                        'Total P/L',
                        _formatReportedAmount(((connected['total_pl'] as num?)?.toDouble() ?? 0.0), currency),
                        ((connected['total_pl'] as num?)?.toDouble() ?? 0.0) >= 0 ? const Color(0xFF4CAF50) : const Color(0xFFFF5252),
                        ((connected['total_pl'] as num?)?.toDouble() ?? 0.0) >= 0 ? const Color(0xFF4CAF50) : const Color(0xFFFF5252),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: isIncreasing ? const Color(0xFF1B5E20).withOpacity(0.2) : const Color(0xFF4A235A).withOpacity(0.2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          isIncreasing ? Icons.trending_up : Icons.trending_down,
                          color: isIncreasing ? const Color(0xFF4CAF50) : const Color(0xFFFF5252),
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              isIncreasing ? 'Balance Increase' : 'Balance Decrease',
                              style: GoogleFonts.poppins(color: Colors.white60, fontSize: 11),
                            ),
                            Text(
                              _formatReportedAmount(balanceChange.abs(), currency),
                              style: GoogleFonts.poppins(
                                color: isIncreasing ? const Color(0xFF4CAF50) : const Color(0xFFFF5252),
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (accountWithdrawals.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Recent Withdrawals', style: GoogleFonts.poppins(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w500)),
                        Text(
                          'Total: ${_formatReportedAmount(totalWithdrawn, currency)}',
                          style: GoogleFonts.poppins(color: const Color(0xFFFFB74D), fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ...accountWithdrawals.take(2).map((withdrawal) {
                      final amount = (withdrawal['amount'] as num?)?.toDouble() ?? 0;
                      final status = withdrawal['status']?.toString() ?? 'pending';
                      final eventType = withdrawal['eventType']?.toString() ?? withdrawal['type']?.toString() ?? 'withdrawal';
                      final eventLabel = eventType
                          .replaceAll('_', ' ')
                          .toUpperCase();
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _formatReportedAmount(amount, currency),
                                    style: GoogleFonts.poppins(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500),
                                  ),
                                  Text(
                                    'Status: $status',
                                    style: GoogleFonts.poppins(color: Colors.white54, fontSize: 10),
                                  ),
                                  Text(
                                    eventLabel,
                                    style: GoogleFonts.poppins(color: const Color(0xFFFFCC80), fontSize: 10, fontWeight: FontWeight.w600),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: _getWithdrawalStatusColor(status).withOpacity(0.2),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                status.toUpperCase(),
                                style: GoogleFonts.poppins(
                                  color: _getWithdrawalStatusColor(status),
                                  fontSize: 9,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  Color _getWithdrawalStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'completed':
      case 'approved':
        return const Color(0xFF4CAF50);
      case 'pending':
        return const Color(0xFFFFB74D);
      case 'failed':
      case 'rejected':
        return const Color(0xFFFF5252);
      default:
        return Colors.white60;
    }
  }

  /// Build recent bots card showing active trading bots
  Widget _buildRecentBotsCard() {
    final activeBots = _activeBotsFor();
    final liveActiveBots = _activeBotsFor('live');
    final demoActiveBots = _activeBotsFor('demo');
    final finishedBots = _finishedBotsFor();
    if (activeBots.isEmpty && finishedBots.isEmpty) {
      return _glassCard(
        child: Column(
          children: [
            Text('Active Bots',
                style: GoogleFonts.poppins(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600)),
            const SizedBox(height: 20),
            if (_botErrorMessage != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  _botErrorMessage!,
                  style: GoogleFonts.poppins(color: const Color(0xFFFF5252), fontSize: 12),
                  textAlign: TextAlign.center,
                ),
              ),
            const Icon(Icons.smart_toy, color: Colors.white24, size: 48),
            const SizedBox(height: 8),
            Text('No active bots', style: GoogleFonts.poppins(color: Colors.white38, fontSize: 13)),
          ],
        ),
      );
    }

    return _glassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Active Bots',
                  style: GoogleFonts.poppins(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600)),
              Text(_balanceMode == 'all' ? '${liveActiveBots.length} live • ${demoActiveBots.length} demo' : '${activeBots.length} active',
                  style: GoogleFonts.poppins(color: const Color(0xFF00E5FF), fontSize: 13, fontWeight: FontWeight.w500)),
            ],
          ),
          const SizedBox(height: 14),
          if (_balanceMode == 'all') ...[
            Row(
              children: [
                Expanded(
                  child: _buildModeSummaryTile(
                    mode: 'live',
                    title: 'Live Bots',
                    value: '${liveActiveBots.length}',
                    subtitle: 'active in live trading',
                    icon: Icons.bolt,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _buildModeSummaryTile(
                    mode: 'demo',
                    title: 'Demo Bots',
                    value: '${demoActiveBots.length}',
                    subtitle: 'active in demo trading',
                    icon: Icons.smart_toy,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
          ],
          ...activeBots.take(5).map((bot) {
            final botId = bot['botId']?.toString() ?? 'Unknown Bot';
            final strategy = bot['strategy']?.toString() ?? 'Unknown';
            final profit = double.tryParse(
                  bot['allTimeProfit']?.toString() ??
                  bot['totalProfit']?.toString() ??
                  bot['profit']?.toString() ??
                  bot['currentProfit']?.toString() ??
                  '0',
                ) ??
                0;
            final isProfitable = profit > 0;
            final botMode = _botMode(bot);
            final botCurrency = _botCurrency(bot);
            final intelligentScanner = bot['intelligentScanner'] == true;
            final scannerMode = bot['scannerMode']?.toString().trim();
            final strategySelectionSummary = _scannerStrategySummary(bot);
            final lastStrategySwitchSummary = _lastStrategySwitchSummary(bot);
            final sizingSummary = _sizingSummary(bot);
            final pyramidSummary = _pyramidSummary(bot);
            
            return Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.06),
                  border: Border.all(color: Colors.white.withOpacity(0.1)),
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Bot info header
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: isProfitable ? const Color(0xFF4CAF50).withOpacity(0.15) : const Color(0xFFFF5252).withOpacity(0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            Icons.smart_toy,
                            color: isProfitable ? const Color(0xFF4CAF50) : const Color(0xFFFF5252),
                            size: 18,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(botId, style: GoogleFonts.poppins(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500)),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: _modeAccent(botMode).withOpacity(0.15),
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                    child: Text(
                                      _modeLabel(botMode),
                                      style: GoogleFonts.poppins(
                                        color: _modeAccent(botMode),
                                        fontSize: 10,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              Text(strategy, style: GoogleFonts.poppins(color: Colors.white54, fontSize: 11)),
                            ],
                          ),
                        ),
                        Text(
                          _formatReportedAmount(profit, botCurrency),
                          style: GoogleFonts.poppins(
                            color: isProfitable ? const Color(0xFF4CAF50) : const Color(0xFFFF5252),
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // Connection status and position age
                    _buildBotStatusRow(bot, botId, botMode),
                    const SizedBox(height: 4),
                    if (strategySelectionSummary != null || lastStrategySwitchSummary != null || sizingSummary != null || pyramidSummary != null) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.18),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.white.withOpacity(0.06)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (strategySelectionSummary != null)
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(
                                    intelligentScanner ? Icons.radar : Icons.auto_awesome,
                                    size: 14,
                                    color: intelligentScanner ? const Color(0xFF00E5FF) : Colors.white54,
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      '${intelligentScanner ? 'Scanner' : 'Auto-select'}${scannerMode != null && scannerMode.isNotEmpty ? ' [$scannerMode]' : ''}: $strategySelectionSummary',
                                      style: GoogleFonts.poppins(
                                        color: Colors.white70,
                                        fontSize: 10.5,
                                        height: 1.35,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            if (strategySelectionSummary != null && lastStrategySwitchSummary != null)
                              const SizedBox(height: 6),
                            if (lastStrategySwitchSummary != null)
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Icon(
                                    Icons.swap_horiz,
                                    size: 14,
                                    color: Color(0xFFFFD166),
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      'Last switch: $lastStrategySwitchSummary',
                                      style: GoogleFonts.poppins(
                                        color: Colors.white60,
                                        fontSize: 10.2,
                                        height: 1.35,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            if ((lastStrategySwitchSummary != null) && (sizingSummary != null || pyramidSummary != null))
                              const SizedBox(height: 6),
                            if (sizingSummary != null)
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Icon(
                                    Icons.speed,
                                    size: 14,
                                    color: Color(0xFF80CBC4),
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      'Sizing: $sizingSummary',
                                      style: GoogleFonts.poppins(
                                        color: Colors.white60,
                                        fontSize: 10.2,
                                        height: 1.35,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            if (sizingSummary != null && pyramidSummary != null)
                              const SizedBox(height: 6),
                            if (pyramidSummary != null)
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Icon(
                                    Icons.trending_up,
                                    size: 14,
                                    color: Color(0xFFFF9E80),
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      'Pyramid: $pyramidSummary',
                                      style: GoogleFonts.poppins(
                                        color: Colors.white60,
                                        fontSize: 10.2,
                                        height: 1.35,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    // Action buttons row
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        // Start button
                        Expanded(
                          child: Consumer<BotService>(
                            builder: (context, botService, _) => InkWell(
                                onTap: () async {
                                  try {
                                    await botService.startBotTrading(botId);
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('Bot $botId started'), duration: const Duration(seconds: 2)),
                                    );
                                    _performRefresh();
                                  } catch (e) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('Error: $e'), duration: const Duration(seconds: 3)),
                                    );
                                  }
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(vertical: 8),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF4CAF50).withOpacity(0.2),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: const Color(0xFF4CAF50).withOpacity(0.5)),
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const Icon(Icons.play_arrow, color: Color(0xFF4CAF50), size: 16),
                                      const SizedBox(width: 4),
                                      Text('Start', style: GoogleFonts.poppins(color: const Color(0xFF4CAF50), fontSize: 12, fontWeight: FontWeight.w500)),
                                    ],
                                  ),
                                ),
                              ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        // Analytics button
                        Expanded(
                          child: InkWell(
                            onTap: () {
                              // Navigate to Bots tab for full analytics
                              Navigator.of(context).pushNamedAndRemoveUntil('/', (_) => false);
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              decoration: BoxDecoration(
                                color: const Color(0xFF00E5FF).withOpacity(0.2),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: const Color(0xFF00E5FF).withOpacity(0.5)),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(Icons.bar_chart, color: Color(0xFF00E5FF), size: 16),
                                  const SizedBox(width: 4),
                                  Text('Analytics', style: GoogleFonts.poppins(color: const Color(0xFF00E5FF), fontSize: 12, fontWeight: FontWeight.w500)),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        // Delete button
                        Expanded(
                          child: InkWell(
                            onTap: () {
                              showDialog(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                  title: Text('Delete Bot?', style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.bold)),
                                  backgroundColor: const Color(0xFF1A1F3A),
                                  content: Text('Are you sure you want to delete bot $botId?', style: GoogleFonts.poppins(color: Colors.white70)),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(ctx),
                                      child: Text('Cancel', style: GoogleFonts.poppins(color: Colors.white54)),
                                    ),
                                    TextButton(
                                      onPressed: () async {
                                        Navigator.pop(ctx);
                                        try {
                                          // Call backend API to delete bot
                                          final prefs = await SharedPreferences.getInstance();
                                          final token = prefs.getString('auth_token') ?? '';
                                          final userId = prefs.getString('user_id');
                                          
                                           final response = await http.post(
                                             Uri.parse('${EnvironmentConfig.apiUrl}/api/bot/delete/$botId'),
                                             headers: {
                                               'Content-Type': 'application/json',
                                               'X-Session-Token': token,
                                             },
                                             body: jsonEncode({
                                               if (userId != null && userId.isNotEmpty) 'user_id': userId,
                                             }),
                                           );
                                          
                                          if (response.statusCode == 200) {
                                            _performRefresh();
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              SnackBar(content: Text('Bot $botId deleted'), duration: const Duration(seconds: 2)),
                                            );
                                          } else {
                                            throw 'Failed to delete bot';
                                          }
                                        } catch (e) {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(content: Text('Error: $e'), duration: const Duration(seconds: 3)),
                                          );
                                        }
                                      },
                                      child: Text('Delete', style: GoogleFonts.poppins(color: const Color(0xFFFF5252), fontWeight: FontWeight.bold)),
                                    ),
                                  ],
                                ),
                              );
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFF5252).withOpacity(0.2),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: const Color(0xFFFF5252).withOpacity(0.5)),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(Icons.delete, color: Color(0xFFFF5252), size: 16),
                                  const SizedBox(width: 4),
                                  Text('Delete', style: GoogleFonts.poppins(color: const Color(0xFFFF5252), fontSize: 12, fontWeight: FontWeight.w500)),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          }),
          if (activeBots.isEmpty) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withOpacity(0.08)),
              ),
              child: Text(
                'No active bots right now. Showing recently finished bots below.',
                style: GoogleFonts.poppins(color: Colors.white60, fontSize: 12),
              ),
            ),
          ],
          ...(() {
            if (finishedBots.isEmpty) return <Widget>[];
            return [
              const SizedBox(height: 20),
              Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: const BoxDecoration(
                      color: Color(0xFFFF5252),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Finished Bots',
                    style: GoogleFonts.poppins(
                      color: const Color(0xFFFF5252),
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '${finishedBots.length}',
                    style: GoogleFonts.poppins(color: Colors.white38, fontSize: 13),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ...finishedBots.map((bot) {
                final fBotId = bot['botId']?.toString() ?? 'Unknown';
                final fProfit = double.tryParse(
                      bot['allTimeProfit']?.toString() ??
                      bot['totalProfit']?.toString() ??
                      bot['profit']?.toString() ??
                      bot['currentProfit']?.toString() ??
                      '0',
                    ) ??
                    0;
                final fTrades = bot['totalTrades']?.toString() ?? '0';
                final fStrategy = bot['strategy']?.toString() ?? 'Unknown';
                final stopReason = bot['stopReason']?.toString();
                final fCurrency = _botCurrency(bot);
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF5252).withOpacity(0.05),
                      border: Border.all(color: const Color(0xFFFF5252).withOpacity(0.25)),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFF5252).withOpacity(0.12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.smart_toy, color: Color(0xFFFF5252), size: 18),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                fBotId,
                                style: GoogleFonts.poppins(
                                    color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w500),
                              ),
                              Text(
                                '$fStrategy • $fTrades trades',
                                style: GoogleFonts.poppins(color: Colors.white38, fontSize: 11),
                              ),
                              if (stopReason != null)
                                Text(
                                  stopReason,
                                  style: GoogleFonts.poppins(
                                      color: const Color(0xFFFF5252), fontSize: 10),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                            ],
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              '${fProfit >= 0 ? '+' : '-'}${_formatReportedAmount(fProfit.abs(), fCurrency)}',
                              style: GoogleFonts.poppins(
                                color: fProfit >= 0
                                    ? const Color(0xFF4CAF50)
                                    : const Color(0xFFFF5252),
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.circle, color: Color(0xFFFF5252), size: 8),
                                SizedBox(width: 4),
                                Text(
                                  'STOPPED',
                                  style: TextStyle(color: Color(0xFFFF5252), fontSize: 10),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ];
          })(),
        ],
      ),
    );
  }
  Widget _glassCard({required Widget child, LinearGradient? gradient}) => Container(
      padding: const EdgeInsets.all(AppDesign.space16),
      decoration: BoxDecoration(
        gradient: gradient,
        color: gradient == null ? Colors.white.withOpacity(AppDesign.opacitySubtle + 0.02) : null,
        borderRadius: BorderRadius.circular(AppDesign.radiusMd),
        border: Border.all(color: Colors.white.withOpacity(AppDesign.opacityBorder)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
            blurRadius: AppDesign.elevationLg,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );

  /// Build the dashboard tab - Modern premium layout
  Widget _buildDashboardTab() => Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF0A0E21), Color(0xFF131831), Color(0xFF0A0E21)],
        ),
      ),
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Backend connection status banner
            Consumer<BotService>(
              builder: (context, botService, _) {
                final connected = botService.isConnected;
                final error = botService.errorMessage;
                if (!connected && error != null) {
                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF5252).withOpacity(0.15),
                      border: Border.all(color: const Color(0xFFFF5252).withOpacity(0.5)),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.error, color: Color(0xFFFF5252), size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Backend disconnected: $error',
                            style: GoogleFonts.poppins(color: Colors.white70, fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  );
                }
                return const SizedBox.shrink();
              },
            ),
            // Error banner if refresh failures detected
            if (_refreshFailureCount > 0)
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFB74D).withOpacity(0.15),
                  border: Border.all(color: const Color(0xFFFFB74D).withOpacity(0.5)),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.warning_amber, color: Color(0xFFFFB74D), size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Connection issues detected. Some data may be outdated.',
                        style: GoogleFonts.poppins(color: const Color(0xFFFFB74D), fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
             _buildPremiumWelcomeCard(),
             const SizedBox(height: 16),
             _buildMLStatusCard(),
             const SizedBox(height: 16),
             _buildSystemIntroCard(),
            const SizedBox(height: 16),
            _buildLiveCandleChart(),
            const SizedBox(height: 16),
            _buildConnectedBrokerCard(),
            const SizedBox(height: 16),
            _buildBrokerAccountsCard(),
            const SizedBox(height: 20),
            _buildQuickStatsRow(),
            const SizedBox(height: 20),
            _buildProfitOverviewCard(),
            const SizedBox(height: 20),
            _buildPortfolioPieChart(),
            const SizedBox(height: 20),
            _buildWinLossDonutChart(),
            const SizedBox(height: 20),
            _buildProfitLineChart(),
            const SizedBox(height: 20),
            _buildTradeAnalysisPreview(),
            const SizedBox(height: 20),
            _buildTopPairsCard(),
            const SizedBox(height: 20),
            _buildRecentTradesCard(),
            const SizedBox(height: 24),
            _buildQuickActionsGrid(),
            const SizedBox(height: 20),
            _buildRecentBotsCard(),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );

  Widget _buildFeatureHubTab() => Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF0A0E21), Color(0xFF151A30), Color(0xFF0A0E21)],
        ),
      ),
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _glassCard(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF1A237E), Color(0xFF283593), Color(0xFF006064)],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Feature Hub',
                    style: GoogleFonts.poppins(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Mobile now exposes the same major operating areas as the web flow: reports, commissions, wallet, broker tools, portfolio views, and automation controls.',
                    style: GoogleFonts.poppins(color: Colors.white70, fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _buildFeatureSection(
              title: 'Reports & Money',
              subtitle: 'Reporting, earnings, wallet, and financial tracking',
              actions: [
                _FeatureAction('Reports', Icons.assessment, const Color(0xFFFF6E40), () => _pushScreen(const ConsolidatedReportsScreen())),
                _FeatureAction('Financials', Icons.attach_money, const Color(0xFF26C6DA), _openFinancials),
                _FeatureAction('Commissions', Icons.monetization_on, const Color(0xFF4CAF50), () => _pushScreen(const CommissionDashboardScreen())),
                _FeatureAction('Wallet', Icons.account_balance_wallet, const Color(0xFFF0B90B), () => _pushScreen(const UserWalletScreen())),
                _FeatureAction('Activity Log', Icons.history, const Color(0xFF8D6E63), () => _pushScreen(const ActivityLogScreen())),
                _FeatureAction('Referrals', Icons.group_add, const Color(0xFF66BB6A), _openReferralDashboard),
              ],
            ),
            const SizedBox(height: 16),
            _buildFeatureSection(
              title: 'Broker & Portfolio',
              subtitle: 'Connected accounts, analytics, portfolio, and broker operations',
              actions: [
                _FeatureAction('Portfolio', Icons.dashboard_customize, const Color(0xFF5C6BC0), () => _pushScreen(const UnifiedBrokerDashboardScreen())),
                _FeatureAction('Broker Setup', Icons.account_tree, const Color(0xFF7C4DFF), () => _pushScreen(const BrokerIntegrationScreen())),
                _FeatureAction('Multi-Broker', Icons.business_center, const Color(0xFFB388FF), () => _pushScreen(const MultiBrokerManagementScreen())),
                _FeatureAction('Accounts', Icons.people, const Color(0xFF00E5FF), () => _pushScreen(const MultiAccountManagementScreen())),
                _FeatureAction('Analytics', Icons.speed, const Color(0xFFFFD600), () => _pushScreen(const BrokerAnalyticsDashboard())),
              ],
            ),
            const SizedBox(height: 16),
            _buildFeatureSection(
              title: 'Automation & Trading',
              subtitle: 'Bot creation, monitoring, strategy tools, and analysis',
              actions: [
                _FeatureAction('Create Bot', Icons.add_circle, const Color(0xFF00C853), () => _pushScreen(const BotConfigurationRoute())),
                _FeatureAction('Bot Monitor', Icons.smart_toy_outlined, const Color(0xFFFFB74D), () => _pushScreen(const BotDashboardScreen())),
                _FeatureAction('Trade Analysis', Icons.analytics_outlined, const Color(0xFF00E5FF), () => _pushScreen(const TradeAnalysisScreen())),
                _FeatureAction('Crypto', Icons.currency_bitcoin, const Color(0xFFF3BA2F), () => _pushScreen(const CryptoStrategiesScreen())),
                _FeatureAction('Trading View', Icons.analytics, const Color(0xFF7C4DFF), () => _pushScreen(const EnhancedDashboardScreen())),
              ],
            ),
            const SizedBox(height: 16),
            _buildFeatureSection(
              title: 'Operations',
              subtitle: 'Features, payouts, and admin-facing operations screens',
              actions: [
                _FeatureAction('Rentals', Icons.card_giftcard, Colors.orangeAccent, () => _pushScreen(const RentalsAndFeaturesScreen())),
                _FeatureAction('FXCM Out', Icons.account_balance_wallet, const Color(0xFF7C4DFF), () => _pushScreen(const FxcmWithdrawalScreen())),
                _FeatureAction('Binance Out', Icons.currency_bitcoin, const Color(0xFFF0B90B), () => _pushScreen(const BinanceWithdrawalScreen())),
                _FeatureAction('Verify', Icons.admin_panel_settings, const Color(0xFFE74C3C), () => _pushScreen(const AdminWithdrawalVerificationScreen())),
                _FeatureAction('VPS Mgmt', Icons.dns, const Color(0xFF00E5FF), () => _pushScreen(const VpsManagementScreen())),
              ],
            ),
            const SizedBox(height: 16),
            _buildSupportSection(),
            const SizedBox(height: 16),
            _buildSystemFeaturesSection(),
          ],
        ),
      ),
    );

  Widget _buildFeatureSection({
    required String title,
    required String subtitle,
    required List<_FeatureAction> actions,
  }) => _glassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: GoogleFonts.poppins(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: GoogleFonts.poppins(color: Colors.white54, fontSize: 11),
          ),
          const SizedBox(height: 14),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 1.45,
            ),
            itemCount: actions.length,
            itemBuilder: (context, index) {
              final action = actions[index];
              return InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: action.onTap,
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        action.color.withOpacity(0.22),
                        action.color.withOpacity(0.08),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: action.color.withOpacity(0.28)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: action.color.withOpacity(0.18),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(action.icon, color: action.color, size: 22),
                      ),
                      Text(
                        action.label,
                        style: GoogleFonts.poppins(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );

  // ── SUPPORT SECTION ──
  Widget _buildSupportSection() => _glassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Support & Contact',
            style: GoogleFonts.poppins(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            'Get help and connect with our support team',
            style: GoogleFonts.poppins(color: Colors.white54, fontSize: 11),
          ),
          const SizedBox(height: 14),
          InkWell(
            onTap: () async {
              const whatsappUrl = 'https://wa.me/27696469651';
              if (await canLaunchUrl(Uri.parse(whatsappUrl))) {
                await launchUrl(Uri.parse(whatsappUrl), mode: LaunchMode.externalApplication);
              }
            },
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [const Color(0xFF25D366).withOpacity(0.22), const Color(0xFF25D366).withOpacity(0.08)],
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFF25D366).withOpacity(0.28)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: const Color(0xFF25D366).withOpacity(0.18),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.chat, color: Color(0xFF25D366), size: 24),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'WhatsApp Support',
                          style: GoogleFonts.poppins(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
                        ),
                        Text(
                          '+27 69 646 9651',
                          style: GoogleFonts.poppins(color: Colors.white70, fontSize: 13),
                        ),
                        Text(
                          'Tap to start chat',
                          style: GoogleFonts.poppins(color: Colors.white54, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.arrow_forward_ios, color: Color(0xFF25D366), size: 16),
                ],
              ),
            ),
          ),
        ],
      ),
    );

  // ── SYSTEM FEATURES SECTION ──
  Widget _buildSystemFeaturesSection() => _glassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'System Functionalities',
            style: GoogleFonts.poppins(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            'Explore what Zwesta Trading System can do for you',
            style: GoogleFonts.poppins(color: Colors.white54, fontSize: 11),
          ),
          const SizedBox(height: 14),
          _buildFeatureItem(
            icon: Icons.business_center,
            title: 'Multi-Broker Integration',
            description: 'Connect and trade across Binance, Luno, FXCM, and Exness simultaneously',
            color: const Color(0xFF7C4DFF),
          ),
          const SizedBox(height: 12),
          _buildFeatureItem(
            icon: Icons.smart_toy,
            title: 'Automated Trading Bots',
            description: 'Create and deploy AI-powered trading strategies that work 24/7',
            color: const Color(0xFFFFB74D),
          ),
          const SizedBox(height: 12),
          _buildFeatureItem(
            icon: Icons.show_chart,
            title: 'Real-Time Market Data',
            description: 'Live price feeds, technical analysis, and market insights',
            color: const Color(0xFF00E5FF),
          ),
          const SizedBox(height: 12),
          _buildFeatureItem(
            icon: Icons.security,
            title: 'Advanced Risk Management',
            description: 'Stop-loss, take-profit, position sizing, and portfolio protection',
            color: const Color(0xFF4CAF50),
          ),
          const SizedBox(height: 12),
          _buildFeatureItem(
            icon: Icons.analytics,
            title: 'Performance Analytics',
            description: 'Detailed trading reports, profit/loss analysis, and strategy optimization',
            color: const Color(0xFFF0B90B),
          ),
          const SizedBox(height: 12),
          _buildFeatureItem(
            icon: Icons.account_balance_wallet,
            title: 'Multi-Currency Support',
            description: 'Trade forex, crypto, commodities, and indices with unified wallet',
            color: const Color(0xFF4CAF50),
          ),
        ],
      ),
    );

  Widget _buildFeatureItem({
    required IconData icon,
    required String title,
    required String description,
    required Color color,
  }) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.poppins(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: GoogleFonts.poppins(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      );

  // ── LIVE CANDLE CHART ──
  Widget _buildLiveCandleChart() => _glassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Live Market',
                style: GoogleFonts.poppins(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Theme.of(context).colorScheme.primary.withOpacity(0.4)),
                ),
                child: Row(
                  children: [
                    AnimatedBuilder(
                      animation: _livePulse,
                      builder: (_, child) => Opacity(
                        opacity: 0.6 + _livePulse.value * 0.4,
                        child: child,
                      ),
                      child: Container(
                        width: 6,
                        height: 6,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'LIVE',
                      style: GoogleFonts.poppins(
                        color: Theme.of(context).colorScheme.primary,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Real-time EUR/USD price action',
            style: GoogleFonts.poppins(color: Colors.white54, fontSize: 11),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 200,
            child: Consumer<TradingService>(
              builder: (context, tradingService, _) {
                final now = DateTime.now();
                final seed = now.millisecondsSinceEpoch % 100000;
                final random = Random(seed);
                final candles = _generateAnimatedCandles(random);
                final lastPrice = candles.isNotEmpty ? candles.last.close : 1.0850;
                final prevPrice = candles.length > 1 ? candles[candles.length - 2].close : lastPrice;
                final priceChange = lastPrice - prevPrice;
                final isUp = priceChange >= 0;
                final priceColor = isUp ? const Color(0xFF4CAF50) : const Color(0xFFFF5252);

                return Stack(
                  children: [
                    LineChart(
                      LineChartData(
                        gridData: FlGridData(
                          show: true,
                          drawVerticalLine: false,
                          horizontalInterval: 0.002,
                          getDrawingHorizontalLine: (value) => FlLine(
                            color: Colors.white.withOpacity(0.08),
                            strokeWidth: 1,
                          ),
                        ),
                        titlesData: FlTitlesData(
                          show: true,
                          rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 30,
                              interval: 5,
                              getTitlesWidget: (value, meta) => Text(
                                '${value.toInt()}:00',
                                style: GoogleFonts.poppins(color: Colors.white54, fontSize: 10),
                              ),
                            ),
                          ),
                          leftTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              interval: 0.002,
                              reservedSize: 40,
                              getTitlesWidget: (value, meta) => Text(
                                value.toStringAsFixed(4),
                                style: GoogleFonts.poppins(color: Colors.white54, fontSize: 10),
                              ),
                            ),
                          ),
                        ),
                        borderData: FlBorderData(show: false),
                        minX: 0,
                        maxX: 23,
                        minY: 1.0800,
                        maxY: 1.0900,
                        lineBarsData: [
                          LineChartBarData(
                            spots: candles.asMap().entries.map((entry) {
                              final c = entry.value;
                              return FlSpot(c.time, c.close);
                            }).toList(),
                            isCurved: true,
                            color: Theme.of(context).colorScheme.primary,
                            barWidth: 2.5,
                            isStrokeCapRound: true,
                            dotData: FlDotData(show: false),
                            belowBarData: BarAreaData(
                              show: true,
                              color: Theme.of(context).colorScheme.primary.withOpacity(0.08),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: priceColor.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              isUp ? Icons.trending_up : Icons.trending_down,
                              color: priceColor,
                              size: 12,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '${priceChange.toStringAsFixed(4)}',
                              style: GoogleFonts.poppins(color: priceColor, fontSize: 10, fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _buildPriceIndicator('Bid', '1.0852', const Color(0xFF4CAF50)),
              const SizedBox(width: 16),
              _buildPriceIndicator('Ask', '1.0854', const Color(0xFFFF5252)),
              const SizedBox(width: 16),
              _buildPriceIndicator('Spread', '2.0 pips', const Color(0xFFFFB74D)),
            ],
          ),
        ],
      ),
    );

  Widget _buildPriceIndicator(String label, String value, Color color) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: GoogleFonts.poppins(color: Colors.white54, fontSize: 10),
          ),
          Text(
            value,
            style: GoogleFonts.poppins(color: color, fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ],
      );

  Widget _buildLiveSparkline() {
    final random = Random();
    final spots = <FlSpot>[];
    var price = 1.0850;
    for (int i = 0; i < 12; i++) {
      price += (random.nextDouble() - 0.5) * 0.0008;
      spots.add(FlSpot(i.toDouble(), price));
    }
    final lastPrice = spots.last.y;
    final prevPrice = spots[spots.length - 2].y;
    final isUp = lastPrice >= prevPrice;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Session Movement',
            style: GoogleFonts.poppins(color: Colors.white54, fontSize: 11),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(
                isUp ? Icons.trending_up : Icons.trending_down,
                color: isUp ? const Color(0xFF4CAF50) : const Color(0xFFFF5252),
                size: 16,
              ),
              const SizedBox(width: 6),
              Text(
                '${(lastPrice - prevPrice).toStringAsFixed(4)}',
                style: GoogleFonts.poppins(
                  color: isUp ? const Color(0xFF4CAF50) : const Color(0xFFFF5252),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                lastPrice.toStringAsFixed(4),
                style: GoogleFonts.poppins(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 40,
            child: LineChart(
              LineChartData(
                gridData: FlGridData(show: false),
                titlesData: FlTitlesData(show: false),
                borderData: FlBorderData(show: false),
                minX: 0,
                maxX: 11,
                minY: spots.map((s) => s.y).reduce(min) - 0.0005,
                maxY: spots.map((s) => s.y).reduce(max) + 0.0005,
                lineBarsData: [
                  LineChartBarData(
                    spots: spots,
                    isCurved: true,
                    color: isUp ? const Color(0xFF4CAF50) : const Color(0xFFFF5252),
                    barWidth: 2,
                    isStrokeCapRound: true,
                    dotData: FlDotData(show: false),
                    belowBarData: BarAreaData(show: false),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<_SampleCandle> _generateAnimatedCandles(Random random) {
    final basePrice = 1.0850;
    final candles = <_SampleCandle>[];

    for (int i = 0; i < 24; i++) {
      final time = i.toDouble();
      final variation = (sin(i * 0.5) * 0.002) + (cos(i * 0.3) * 0.001) + (random.nextDouble() * 0.0005 - 0.00025);
      final close = basePrice + variation;
      candles.add(_SampleCandle(time: time, close: close));
    }

    return candles;
  }

  List<_SampleCandle> _generateSampleCandles() {
    final basePrice = 1.0850;
    final candles = <_SampleCandle>[];
    final random = Random();

    for (int i = 0; i < 24; i++) {
      final time = i.toDouble();
      final variation = (sin(i * 0.5) * 0.002) + (cos(i * 0.3) * 0.001) + (random.nextDouble() * 0.0005 - 0.00025);
      final close = basePrice + variation;
      candles.add(_SampleCandle(time: time, close: close));
    }

    return candles;
  }

  // ── ML STATUS CARD ──
  // Shows whether ML models are active and their health status
  Widget _buildMLStatusCard() {
    return Consumer<MLStatusService>(
      builder: (context, mlStatus, _) {
        final isReady = mlStatus.isReady;
        final health = mlStatus.health;
        final activeModels = health['activeModels'] ?? 0;
        final totalModels = health['totalModels'] ?? 6;
        
        return GestureDetector(
          onTap: () => _showMLDetails(context, mlStatus),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: isReady
                    ? [const Color(0xFF00C853).withOpacity(0.15), const Color(0xFF00E676).withOpacity(0.05)]
                    : [const Color(0xFFFF6D00).withOpacity(0.15), const Color(0xFFFF9100).withOpacity(0.05)],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ),
              borderRadius: BorderRadius.circular(AppDesign.radiusMd),
              border: Border.all(
                color: isReady
                    ? const Color(0xFF00C853).withOpacity(0.5)
                    : const Color(0xFFFF6D00).withOpacity(0.5),
              ),
            ),
            child: Row(
              children: [
                // Pulsing indicator
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isReady ? const Color(0xFF00E676) : const Color(0xFFFF9100),
                    boxShadow: [
                      BoxShadow(
                        color: (isReady ? const Color(0xFF00E676) : const Color(0xFFFF9100)).withOpacity(0.6),
                        blurRadius: isReady ? 8 : 4,
                        spreadRadius: isReady ? 2 : 1,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                // ML Icon
                Icon(
                  Icons.psychology_outlined,
                  color: isReady ? const Color(0xFF00E676) : const Color(0xFFFF9100),
                  size: 22,
                ),
                const SizedBox(width: 10),
                // Status text
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isReady ? 'ML Engine Active' : 'ML Engine Standby',
                        style: GoogleFonts.poppins(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        '$activeModels/$totalModels models loaded • ${health['statusText'] ?? 'Initializing'}',
                        style: GoogleFonts.poppins(
                          color: Colors.white54,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                // Arrow
                Icon(
                  Icons.chevron_right,
                  color: Colors.white38,
                  size: 20,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showMLDetails(BuildContext context, MLStatusService mlStatus) {
    final health = mlStatus.health;
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF111633),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('ML Engine Status', style: GoogleFonts.poppins(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 16),
            _mlStatusRow('Regime Filter', health['regime'] ?? false),
            _mlStatusRow('Signal Scorer', health['signal_scorer'] ?? false),
            _mlStatusRow('Dynamic SL/TP', health['dynamic_sltp'] ?? false),
            _mlStatusRow('Smart Exits', health['smart_exit'] ?? false),
            _mlStatusRow('Portfolio Allocator', health['portfolio'] ?? true),
            _mlStatusRow('Anomaly Detector', health['anomaly'] ?? false),
            const SizedBox(height: 16),
            Text(
              'ML models analyze market conditions, score signals, optimize exits, and manage risk in real-time.',
              style: GoogleFonts.poppins(color: Colors.white54, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _mlStatusRow(String name, bool active) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(
            active ? Icons.check_circle : Icons.radio_button_unchecked,
            color: active ? const Color(0xFF00E676) : Colors.white38,
            size: 18,
          ),
          const SizedBox(width: 10),
          Text(name, style: GoogleFonts.poppins(color: Colors.white70, fontSize: 13)),
          const Spacer(),
          Text(
            active ? 'Active' : 'Standby',
            style: GoogleFonts.poppins(
              color: active ? const Color(0xFF00E676) : Colors.white38,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  // ── SYSTEM INTRO CARD ──
  // Short pitch shown on the dashboard so new users instantly understand
  // what Zwesta does and which brokers it auto-trades on.
  Widget _buildSystemIntroCard() => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              const Color(0xFF7C4DFF).withOpacity(0.18),
              const Color(0xFF00E5FF).withOpacity(0.12),
            ],
          ),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white.withOpacity(0.10)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF00E5FF).withOpacity(0.18),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.auto_awesome,
                      color: Color(0xFF00E5FF), size: 20),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'How Zwesta works for you',
                    style: GoogleFonts.poppins(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      letterSpacing: 0.2,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              'Zwesta is an automated trading system. You configure bots once '
              'and our engine scans the markets, scores signals, manages risk, '
              'and places trades for you on the brokers below — across crypto, '
              'forex and commodities, in demo or live mode.',
              style: GoogleFonts.poppins(
                color: Colors.white.withOpacity(0.82),
                fontSize: 12.5,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'Trades placed on:',
              style: GoogleFonts.poppins(
                color: Colors.white60,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _brokerBadge(
                  icon: '₿',
                  label: 'Binance',
                  color: const Color(0xFFF3BA2F),
                  subtitle: 'Crypto spot',
                ),
                const SizedBox(width: 8),
                _brokerBadge(
                  icon: 'L',
                  label: 'Luno',
                  color: const Color(0xFF03A9F4),
                  subtitle: 'Crypto spot',
                ),
                const SizedBox(width: 8),
                _brokerBadge(
                  icon: 'E',
                  label: 'Exness',
                  color: const Color(0xFF00E5FF),
                  subtitle: 'FX & metals',
                ),
                const SizedBox(width: 8),
                _brokerBadge(
                  icon: 'F',
                  label: 'FXCM',
                  color: const Color(0xFF7C4DFF),
                  subtitle: 'Forex',
                ),
              ],
            ),
          ],
        ),
      );

  Widget _brokerBadge({
    required String icon,
    required String label,
    required Color color,
    required String subtitle,
  }) {
    final assetName = 'assets/images/${label.toLowerCase()}.png';
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: color.withOpacity(0.10),
          border: Border.all(color: color.withOpacity(0.45)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Image.asset(
                assetName,
                width: 32,
                height: 32,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  width: 28,
                  height: 28,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.20),
                    shape: BoxShape.circle,
                    border: Border.all(color: color),
                  ),
                  child: Text(
                    icon,
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: GoogleFonts.poppins(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: GoogleFonts.poppins(
                      color: Colors.white60,
                      fontSize: 9.5,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── PREMIUM WELCOME CARD ──
  Widget _buildPremiumWelcomeCard() => Consumer<AuthService>(
      builder: (context, authService, _) {
        final name = authService.currentUser?.firstName ?? 'Trader';
        final hour = DateTime.now().hour;
        final greeting = hour < 12 ? 'Good Morning' : hour < 18 ? 'Good Afternoon' : 'Good Evening';
        
        return _glassCard(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Theme.of(context).colorScheme.primary.withOpacity(0.18),
              Theme.of(context).colorScheme.secondary.withOpacity(0.10),
              const Color(0xFF0A0E21),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 50,
                    height: 50,
                     decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [
                          Theme.of(context).colorScheme.primary.withOpacity(0.7),
                          Theme.of(context).colorScheme.secondary.withOpacity(0.6),
                        ],
                      ),
                    ),
                    child: Center(
                      child: Text(
                        name[0].toUpperCase(),
                        style: GoogleFonts.poppins(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          greeting,
                          style: GoogleFonts.poppins(color: Colors.white60, fontSize: 13),
                        ),
                        Text(
                          name,
                          style: GoogleFonts.poppins(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                    Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.10),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white.withOpacity(0.15)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AnimatedBuilder(
                          animation: _livePulse,
                          builder: (_, child) => Opacity(
                            opacity: 0.6 + _livePulse.value * 0.4,
                            child: child,
                          ),
                          child: Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: const Color(0xFF4CAF50),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFF4CAF50).withOpacity(0.4 * (0.6 + _livePulse.value * 0.4)),
                                  blurRadius: 6,
                                  spreadRadius: 1,
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Online',
                          style: GoogleFonts.poppins(color: Colors.white70, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
               const SizedBox(height: 16),
              if (_recentWithdrawals.isNotEmpty) ...[
                _buildLiveSparkline(),
                const SizedBox(height: 18),
              ],
              // ── Demo / Live Toggle ──
              Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    for (final mode in [{'key': 'all', 'label': 'All'}, {'key': 'live', 'label': 'Live'}, {'key': 'demo', 'label': 'Demo'}])
                      Expanded(
                        child: GestureDetector(
                          onTap: () => _setBalanceMode(mode['key']!),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            decoration: BoxDecoration(
                               color: _balanceMode == mode['key'] ? Theme.of(context).colorScheme.primary : Colors.transparent,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Center(
                              child: Text(
                                mode['label']!,
                                style: GoogleFonts.poppins(
                                  color: _balanceMode == mode['key'] ? Colors.white : Colors.white54,
                                  fontSize: 12,
                                  fontWeight: _balanceMode == mode['key'] ? FontWeight.w600 : FontWeight.w400,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Text(
                    'Report In',
                    style: GoogleFonts.poppins(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(width: 10),
                  _buildDashboardSelectorPill(
                    label: r'$ USD',
                    selected: _reportingCurrency == 'USD',
                    onTap: () => _setReportingCurrency('USD'),
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
                  ),
                  const SizedBox(width: 8),
                  _buildDashboardSelectorPill(
                    label: 'R ZAR',
                    selected: _reportingCurrency == 'ZAR',
                    onTap: () => _setReportingCurrency('ZAR'),
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // ── Total Portfolio Balance ──
              Builder(
                builder: (context) {
                  final filteredAll = _applyPortfolioBrokerFilter(_filteredBrokerAccounts());
                  final liveAllAccounts = _applyPortfolioBrokerFilter(_filteredBrokerAccounts('live'));
                  final demoAllAccounts = _applyPortfolioBrokerFilter(_filteredBrokerAccounts('demo'));
                  final filteredConnected = _applyPortfolioBrokerFilter(_connectedAccountsFor());
                  final liveConnectedAccounts = _applyPortfolioBrokerFilter(_connectedAccountsFor('live'));
                  final demoConnectedAccounts = _applyPortfolioBrokerFilter(_connectedAccountsFor('demo'));
                  final filtered = filteredConnected.isNotEmpty ? filteredConnected : filteredAll;
                  final liveAccounts = liveConnectedAccounts.isNotEmpty ? liveConnectedAccounts : liveAllAccounts;
                  final demoAccounts = demoConnectedAccounts.isNotEmpty ? demoConnectedAccounts : demoAllAccounts;
                  final filteredTotals = _aggregateAccountBalances(
                    filtered,
                    respectPortfolioTotalsFlag: _balanceMode == 'all',
                  );
                  final connectedCount = filtered.where((a) => a['connected'] == true).length;

                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _balanceMode == 'all' ? 'TOTAL PORTFOLIO BALANCE' :
                          _balanceMode == 'live' ? 'LIVE BALANCE' : 'DEMO BALANCE',
                          style: GoogleFonts.poppins(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.w500, letterSpacing: 1.2),
                        ),
                        const SizedBox(height: 4),
                        if (_brokerBalancesLoading && _totalBrokerBalance == 0) Row(
                                children: [
                                  const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 1.5, color: Color(0xFF00E5FF))),
                                  const SizedBox(width: 10),
                                  Text('Loading...', style: GoogleFonts.poppins(color: Colors.white38, fontSize: 14)),
                                ],
                              ) else Text(
                                _formatCurrencyBreakdown(filteredTotals),
                                style: GoogleFonts.poppins(
                                  color: Colors.white,
                                  fontSize: 28,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                        if (connectedCount > 0)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              '$connectedCount ${_balanceMode == 'all' ? 'connected' : _balanceMode} account${connectedCount == 1 ? '' : 's'} • reporting in $_reportingCurrency',
                              style: GoogleFonts.poppins(color: Colors.white38, fontSize: 11),
                            ),
                          ),
                        if (_balanceMode == 'all') ...[
                          const SizedBox(height: 14),
                          Column(
                            children: [
                              _buildModeSummaryTile(
                                mode: 'live',
                                title: 'Live Balance',
                                value: _formatCurrencyBreakdown(_aggregateAccountBalances(liveAccounts)),
                                subtitle: '${liveAccounts.where((a) => a['connected'] == true).length} connected live account${liveAccounts.where((a) => a['connected'] == true).length == 1 ? '' : 's'}',
                                icon: Icons.trending_up,
                              ),
                              const SizedBox(height: 10),
                              _buildModeSummaryTile(
                                mode: 'demo',
                                title: 'Demo Balance',
                                value: _formatCurrencyBreakdown(_aggregateAccountBalances(demoAccounts)),
                                subtitle: '${demoAccounts.where((a) => a['connected'] == true).length} connected demo account${demoAccounts.where((a) => a['connected'] == true).length == 1 ? '' : 's'}',
                                icon: Icons.science,
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  );
                },
              ),
            ],
          ),
        );
      },
    );

  // ── BROKER ACCOUNTS CARD ──
  Widget _buildBrokerAccountsCard() {
    final shownAccounts = _filteredBrokerAccounts();
    final liveAccounts = _filteredBrokerAccounts('live');
    final demoAccounts = _filteredBrokerAccounts('demo');

    return _glassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Broker Accounts', style: GoogleFonts.poppins(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600)),
          const SizedBox(height: 14),
          if (_balanceMode == 'all') ...[
            Column(
              children: [
                _buildModeSummaryTile(
                  mode: 'live',
                  title: 'Live Accounts',
                  value: _formatCurrencyBreakdown(_aggregateAccountBalances(liveAccounts)),
                  subtitle: '${liveAccounts.length} live account${liveAccounts.length == 1 ? '' : 's'} on dashboard',
                  icon: Icons.account_balance,
                ),
                const SizedBox(height: 10),
                _buildModeSummaryTile(
                  mode: 'demo',
                  title: 'Demo Accounts',
                  value: _formatCurrencyBreakdown(_aggregateAccountBalances(demoAccounts)),
                  subtitle: '${demoAccounts.length} demo account${demoAccounts.length == 1 ? '' : 's'} on dashboard',
                  icon: Icons.account_balance_wallet,
                ),
              ],
            ),
            const SizedBox(height: 14),
          ],
          ...shownAccounts.map((account) {
            final broker = account['broker']?.toString() ?? 'Unknown';
            final accountNum = account['accountNumber']?.toString() ?? '';
            final balance = (account['balance'] as num?)?.toDouble() ?? 0;
            final equity = (account['equity'] as num?)?.toDouble() ?? 0;
            final mode = _accountMode(account);
            final connected = account['connected'] == true;
            final error = account['error']?.toString();
            final warning = account['warning']?.toString();
            final acctCurrency = (account['currency'] as String? ?? 'USD').toUpperCase();
            final dataSource = (account['dataSource'] ?? '').toString();
            final isStale = dataSource == 'stale_cache';
            final brokerColor = _brokerAccentColor(broker);

            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.04),
                borderRadius: BorderRadius.circular(12),
                border: isStale
                    ? Border.all(color: const Color(0xFFFFB74D).withOpacity(0.3))
                    : null,
              ),
              child: Row(
                children: [
                  Container(
                    width: 40, height: 40,
                    decoration: BoxDecoration(
                      color: isStale
                          ? const Color(0xFFFFB74D).withOpacity(0.15)
                          : (connected || balance > 0)
                              ? brokerColor.withOpacity(0.15)
                              : const Color(0xFFFF5252).withOpacity(0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      isStale
                          ? Icons.access_time
                          : (connected || balance > 0) ? _brokerIcon(broker) : Icons.error_outline,
                      color: isStale
                          ? const Color(0xFFFFB74D)
                          : (connected || balance > 0) ? brokerColor : const Color(0xFFFF5252),
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text('$broker',
                                style: GoogleFonts.poppins(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500)),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: _modeAccent(mode).withOpacity(0.15),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                _modeLabel(mode),
                                style: GoogleFonts.poppins(
                                  color: _modeAccent(mode),
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                        Text('Account: $accountNum',
                          style: GoogleFonts.poppins(color: Colors.white38, fontSize: 10)),
                        if (!connected && balance == 0 && error != null)
                          Text(error, style: GoogleFonts.poppins(color: const Color(0xFFFF5252), fontSize: 10)),
                        if (warning != null)
                          Text(warning, style: GoogleFonts.poppins(color: const Color(0xFFFFB74D), fontSize: 10)),
                      ],
                    ),
                  ),
                  if (balance > 0 || connected)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(_formatReportedAmount(balance, acctCurrency),
                          style: GoogleFonts.poppins(
                            color: isStale ? const Color(0xFFFFB74D) : Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text('Equity: ${_formatReportedAmount(equity, acctCurrency)}',
                          style: GoogleFonts.poppins(color: Colors.white54, fontSize: 10)),
                        if (isStale)
                          Text('STALE', style: GoogleFonts.poppins(color: const Color(0xFFFFB74D), fontSize: 9, fontWeight: FontWeight.w700)),
                      ],
                    ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  // ── QUICK STATS ROW ──
  Widget _buildQuickStatsRow() {
    final selectedBots = _filteredBots();
    final activeBots = _activeBotsFor().length;
    final liveActiveBots = _activeBotsFor('live').length;
    final demoActiveBots = _activeBotsFor('demo').length;
    final totalTrades = selectedBots.fold<int>(
      0, (sum, bot) => sum + (int.tryParse(bot['totalTrades']?.toString() ?? '0') ?? 0),
    );
    final totalProfitByCurrency = _aggregateBotValuesFor('profit');
    final totalProfit = totalProfitByCurrency.values.fold<double>(0, (sum, value) => sum + value);

    return Row(
      children: [
        Expanded(child: _buildStatPill(Icons.smart_toy, _balanceMode == 'all' ? 'Live $liveActiveBots / Demo $demoActiveBots' : '$activeBots', 'Active Bots', const Color(0xFF7C4DFF), valueFontSize: _balanceMode == 'all' ? 12 : 20)),
        const SizedBox(width: 10),
        Expanded(child: _buildStatPill(Icons.swap_horiz, '$totalTrades', 'Trades', const Color(0xFF00E5FF))),
        const SizedBox(width: 10),
        Expanded(
          child: _buildStatPill(
            totalProfit >= 0 ? Icons.trending_up : Icons.trending_down,
            _formatCurrencyBreakdown(totalProfitByCurrency, decimals: 0),
            'Profit',
            totalProfit >= 0 ? const Color(0xFF4CAF50) : const Color(0xFFFF5252),
          ),
        ),
      ],
    );
  }

  Widget _buildBotStatusRow(Map<String, dynamic> bot, String botId, String botMode) {
    final openPositions = bot['openPositions'];
    final positionCount = openPositions is List
        ? openPositions.length
        : (openPositions is Map ? openPositions.length : 0);
    final hasPositions = positionCount > 0;
    final isRunning = bot['isRunning'] == true || bot['enabled'] == true;
    final lastTrade = bot['lastTradeTime']?.toString();
    final ageStr = _computePositionAge(bot);
    final brokerName = (bot['brokerName'] ?? bot['broker_type'] ?? 'MT5').toString();

    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: isRunning
                ? const Color(0xFF4CAF50).withOpacity(0.15)
                : const Color(0xFFFF5252).withOpacity(0.15),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            children: [
              Icon(
                isRunning ? Icons.circle : Icons.stop,
                size: 8,
                color: isRunning ? const Color(0xFF4CAF50) : const Color(0xFFFF5252),
              ),
              const SizedBox(width: 4),
              Text(
                isRunning ? 'Running' : 'Stopped',
                style: GoogleFonts.poppins(
                  color: isRunning ? const Color(0xFF4CAF50) : const Color(0xFFFF5252),
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        if (hasPositions) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.08),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              '$positionCount ${positionCount == 1 ? 'position' : 'positions'} • $brokerName',
              style: GoogleFonts.poppins(color: Colors.white60, fontSize: 10),
            ),
          ),
          const SizedBox(width: 8),
        ],
        if (ageStr.isNotEmpty)
          Text(
            'Age: $ageStr',
            style: GoogleFonts.poppins(color: Colors.white54, fontSize: 10),
          ),
        const Spacer(),
        if (lastTrade != null)
          Text(
            'Last: ${_formatTimestamp(lastTrade)}',
            style: GoogleFonts.poppins(color: Colors.white54, fontSize: 10),
          ),
      ],
    );
  }

  String _computePositionAge(Map<String, dynamic> bot) {
    final openPositions = bot['openPositions'];
    DateTime? oldestTime;
    if (openPositions is List) {
      for (final pos in openPositions) {
        if (pos is Map) {
          final t = pos['openedAt'] ?? pos['time_open'] ?? pos['openTime'];
          if (t != null) {
            final dt = DateTime.tryParse(t.toString());
            if (dt != null && (oldestTime == null || dt.isBefore(oldestTime))) {
              oldestTime = dt;
            }
          }
        }
      }
    } else if (openPositions is Map) {
      for (final pos in openPositions.values) {
        if (pos is Map) {
          final t = pos['openedAt'] ?? pos['time_open'] ?? pos['openTime'];
          if (t != null) {
            final dt = DateTime.tryParse(t.toString());
            if (dt != null && (oldestTime == null || dt.isBefore(oldestTime))) {
              oldestTime = dt;
            }
          }
        }
      }
    }
    if (oldestTime == null) return '';
    final diff = DateTime.now().difference(oldestTime);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h ${diff.inMinutes % 60}m';
    return '${diff.inDays}d ${diff.inHours % 24}h';
  }

  String _formatTimestamp(String ts) {
    final dt = DateTime.tryParse(ts);
    if (dt == null) return ts;
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  Widget _buildStatPill(IconData icon, String value, String label, Color color, {double valueFontSize = 20}) => _glassCard(
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(height: 10),
          Text(
            value,
            textAlign: TextAlign.center,
            maxLines: 2,
            style: GoogleFonts.poppins(
              color: Colors.white,
              fontSize: valueFontSize,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: GoogleFonts.poppins(color: Colors.white54, fontSize: 11),
          ),
        ],
      ),
    );

  // ── PROFIT OVERVIEW ──
  Widget _buildProfitOverviewCard() {
    final selectedBots = _filteredBots();
    final totalProfitByCurrency = _aggregateBotValuesFor('profit');
    final liveProfitByCurrency = _aggregateBotValuesFor('profit', mode: 'live');
    final demoProfitByCurrency = _aggregateBotValuesFor('profit', mode: 'demo');
    final totalProfit = totalProfitByCurrency.values.fold<double>(0, (sum, value) => sum + value);
    final profitableBots = selectedBots.where((bot) => (double.tryParse(bot['profit']?.toString() ?? '0') ?? 0) > 0).length;
    final totalBots = selectedBots.length;
    final profitableBotsRate = totalBots > 0 ? (profitableBots / totalBots * 100) : 0.0;
    final liveWinningBots = _filteredBots('live').where((bot) => (double.tryParse(bot['profit']?.toString() ?? '0') ?? 0) > 0).length;
    final demoWinningBots = _filteredBots('demo').where((bot) => (double.tryParse(bot['profit']?.toString() ?? '0') ?? 0) > 0).length;
    final liveBotsCount = _filteredBots('live').length;
    final demoBotsCount = _filteredBots('demo').length;

    return _glassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Profit Overview',
                  style: GoogleFonts.poppins(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: totalProfit >= 0
                      ? const Color(0xFF4CAF50).withOpacity(0.15)
                      : const Color(0xFFFF5252).withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  totalProfit >= 0 ? 'Profitable' : 'In Drawdown',
                  style: GoogleFonts.poppins(
                    color: totalProfit >= 0 ? const Color(0xFF4CAF50) : const Color(0xFFFF5252),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Center(
            child: Text(
              _formatCurrencyBreakdown(totalProfitByCurrency),
              style: GoogleFonts.poppins(
                color: totalProfit >= 0 ? const Color(0xFF4CAF50) : const Color(0xFFFF5252),
                fontSize: 36,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Center(
            child: Text('Total Net Return',
                style: GoogleFonts.poppins(color: Colors.white38, fontSize: 12)),
          ),
          if (_balanceMode == 'all') ...[
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: _buildModeSummaryTile(
                    mode: 'live',
                    title: 'Live Profit',
                    value: _formatCurrencyBreakdown(liveProfitByCurrency),
                    subtitle: '${liveWinningBots}/${liveBotsCount} profitable live bots',
                    icon: Icons.show_chart,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _buildModeSummaryTile(
                    mode: 'demo',
                    title: 'Demo Profit',
                    value: _formatCurrencyBreakdown(demoProfitByCurrency),
                    subtitle: '${demoWinningBots}/${demoBotsCount} profitable demo bots',
                    icon: Icons.insights,
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 24),
          // Profitable Bots Bar
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              height: 10,
              child: LinearProgressIndicator(
                value: profitableBotsRate / 100,
                backgroundColor: Colors.white10,
                valueColor: const AlwaysStoppedAnimation(Color(0xFF00E5FF)),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Profitable Bots: ${profitableBotsRate.toStringAsFixed(1)}%',
                style: GoogleFonts.poppins(color: const Color(0xFF00E5FF), fontSize: 13, fontWeight: FontWeight.w600),
              ),
              Text(
                '$profitableBots / $totalBots bots profitable',
                style: GoogleFonts.poppins(color: Colors.white38, fontSize: 11),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── PORTFOLIO DISTRIBUTION PIE CHART ──
  Widget _buildPortfolioPieChart() {
    final selectedBots = _filteredBots();
    final symbolProfits = <String, double>{};
    for (final bot in selectedBots) {
      final symbols = bot['symbol']?.toString() ?? 'EURUSD';
      final profit = (double.tryParse(bot['profit']?.toString() ?? '0') ?? 0).abs();
      if (profit > 0) {
        symbolProfits[symbols] = (symbolProfits[symbols] ?? 0) + profit;
      }
    }

    if (symbolProfits.isEmpty) {
      return _glassCard(
        child: Column(
          children: [
            Text('Portfolio Distribution',
                style: GoogleFonts.poppins(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600)),
            const SizedBox(height: 20),
            const Icon(Icons.pie_chart_outline, color: Colors.white24, size: 48),
            const SizedBox(height: 8),
            Text('No trading data yet', style: GoogleFonts.poppins(color: Colors.white38, fontSize: 13)),
          ],
        ),
      );
    }

    final chartColors = [
      const Color(0xFF00E5FF),
      const Color(0xFF4CAF50),
      const Color(0xFFFFD600),
      const Color(0xFFFF5252),
      const Color(0xFF7C4DFF),
      const Color(0xFFFF6E40),
      const Color(0xFF40C4FF),
      const Color(0xFFB388FF),
    ];

    final total = symbolProfits.values.fold<double>(0, (s, v) => s + v);
    final entries = symbolProfits.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

    return _glassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Portfolio Distribution',
              style: GoogleFonts.poppins(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600)),
          const SizedBox(height: 20),
          SizedBox(
            height: 200,
            child: PieChart(
              PieChartData(
                sectionsSpace: 3,
                centerSpaceRadius: 45,
                sections: entries.asMap().entries.map((e) {
                  final i = e.key;
                  final pair = e.value;
                  final pct = pair.value / total * 100;
                  final color = chartColors[i % chartColors.length];
                  return PieChartSectionData(
                    value: pair.value,
                    color: color,
                    radius: 55,
                    title: '${pct.toStringAsFixed(0)}%',
                    titleStyle: GoogleFonts.poppins(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: entries.asMap().entries.map((e) {
              final i = e.key;
              final pair = e.value;
              final color = chartColors[i % chartColors.length];
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(width: 10, height: 10, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
                  const SizedBox(width: 6),
                  Text(pair.key, style: GoogleFonts.poppins(color: Colors.white70, fontSize: 11)),
                ],
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  // ── WIN / LOSS DONUT CHART ──
  Widget _buildWinLossDonutChart() {
    final winningBots = _realBotsList.where((b) => (double.tryParse(b['profit']?.toString() ?? '0') ?? 0) > 0).length;
    final losingBots = _realBotsList.where((b) => (double.tryParse(b['profit']?.toString() ?? '0') ?? 0) < 0).length;
    final breakEven = _realBotsList.length - winningBots - losingBots;
    final total = _realBotsList.length;

    if (total == 0) {
      return _glassCard(
        child: Column(
          children: [
            Text('Win / Loss Ratio',
                style: GoogleFonts.poppins(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600)),
            const SizedBox(height: 20),
            const Icon(Icons.donut_large, color: Colors.white24, size: 48),
            const SizedBox(height: 8),
            Text('No bots running', style: GoogleFonts.poppins(color: Colors.white38, fontSize: 13)),
          ],
        ),
      );
    }

    return _glassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Win / Loss Ratio',
              style: GoogleFonts.poppins(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600)),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 160,
                  child: PieChart(
                    PieChartData(
                      sectionsSpace: 2,
                      centerSpaceRadius: 35,
                      sections: [
                        if (winningBots > 0)
                          PieChartSectionData(
                            value: winningBots.toDouble(),
                            color: const Color(0xFF4CAF50),
                            radius: 40,
                            title: '$winningBots',
                            titleStyle: GoogleFonts.poppins(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                          ),
                        if (losingBots > 0)
                          PieChartSectionData(
                            value: losingBots.toDouble(),
                            color: const Color(0xFFFF5252),
                            radius: 40,
                            title: '$losingBots',
                            titleStyle: GoogleFonts.poppins(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                          ),
                        if (breakEven > 0)
                          PieChartSectionData(
                            value: breakEven.toDouble(),
                            color: Colors.white30,
                            radius: 40,
                            title: '$breakEven',
                            titleStyle: GoogleFonts.poppins(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 20),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _chartLegendItem(const Color(0xFF4CAF50), 'Winning', winningBots),
                  const SizedBox(height: 10),
                  _chartLegendItem(const Color(0xFFFF5252), 'Losing', losingBots),
                  const SizedBox(height: 10),
                  _chartLegendItem(Colors.white30, 'Break Even', breakEven),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _chartLegendItem(Color color, String label, int count) => Row(
      children: [
        Container(width: 12, height: 12, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
        const SizedBox(width: 8),
        Text('$label ($count)', style: GoogleFonts.poppins(color: Colors.white70, fontSize: 12)),
      ],
    );

  /// Build individual metric card for account dashboard
  Widget _buildMetricCard(String label, String value, Color valueColor, Color accentColor) => Container(
      decoration: BoxDecoration(
        border: Border.all(color: accentColor.withOpacity(AppDesign.opacityBorderStrong)),
        borderRadius: BorderRadius.circular(AppDesign.radiusMd),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            accentColor.withOpacity(0.08),
            accentColor.withOpacity(AppDesign.opacitySubtle),
          ],
        ),
      ),
      padding: const EdgeInsets.all(AppDesign.space12),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: GoogleFonts.poppins(
              color: Colors.white.withOpacity(AppDesign.opacityMuted),
              fontSize: 10,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: AppDesign.space6),
          Text(
            value,
            style: GoogleFonts.poppins(
              color: valueColor,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );

  // ── PROFIT TREND LINE CHART ──
  Widget _buildProfitLineChart() {
    final selectedBots = _filteredBots();
    final currency = _preferredProfitCurrency();
    // Gather profit per bot as data points
    final profitPoints = <FlSpot>[];
    double cumulative = 0;
    for (var i = 0; i < selectedBots.length; i++) {
      final profit = double.tryParse(selectedBots[i]['profit']?.toString() ?? '0') ?? 0;
      cumulative += profit;
      profitPoints.add(FlSpot(i.toDouble(), cumulative));
    }

    if (profitPoints.isEmpty) {
      return _glassCard(
        child: Column(
          children: [
            Text('Cumulative Profit Trend',
                style: GoogleFonts.poppins(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600)),
            const SizedBox(height: 20),
            const Icon(Icons.show_chart, color: Colors.white24, size: 48),
            const SizedBox(height: 8),
            Text('No data yet', style: GoogleFonts.poppins(color: Colors.white38, fontSize: 13)),
          ],
        ),
      );
    }

    final maxY = profitPoints.map((p) => p.y).reduce(max);
    final minY = profitPoints.map((p) => p.y).reduce(min);
    final range = (maxY - minY).abs();
    final padding = range > 0 ? range * 0.2 : 10.0;

    return _glassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Cumulative Profit Trend',
              style: GoogleFonts.poppins(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(
            'Across ${selectedBots.length} bot(s)',
            style: GoogleFonts.poppins(color: Colors.white38, fontSize: 11),
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 200,
            child: LineChart(
              LineChartData(
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: range > 0 ? range / 4 : 5,
                  getDrawingHorizontalLine: (value) =>
                      const FlLine(color: Colors.white10, strokeWidth: 1),
                ),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 50,
                      getTitlesWidget: (value, meta) => Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: Text(
                          _formatCurrencyAmount(value, currency, decimals: 0),
                          style: GoogleFonts.poppins(color: Colors.white38, fontSize: 9),
                        ),
                      ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (value, meta) {
                        final idx = value.toInt();
                        if (idx >= 0 && idx < selectedBots.length) {
                          final botId = (selectedBots[idx]['botId'] ?? '').toString();
                          return Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              botId.length > 5 ? botId.substring(0, 5) : botId,
                              style: GoogleFonts.poppins(color: Colors.white38, fontSize: 8),
                            ),
                          );
                        }
                        return const SizedBox.shrink();
                      },
                    ),
                  ),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                ),
                borderData: FlBorderData(show: false),
                minY: minY - padding,
                maxY: maxY + padding,
                lineBarsData: [
                  LineChartBarData(
                    spots: profitPoints,
                    isCurved: true,
                    curveSmoothness: 0.3,
                    color: const Color(0xFF00E5FF),
                    barWidth: 3,
                    dotData: FlDotData(
                      show: true,
                      getDotPainter: (spot, percent, bar, index) =>
                          FlDotCirclePainter(
                        radius: 4,
                        color: spot.y >= 0 ? const Color(0xFF4CAF50) : const Color(0xFFFF5252),
                        strokeColor: Colors.white,
                        strokeWidth: 1.5,
                      ),
                    ),
                    belowBarData: BarAreaData(
                      show: true,
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          const Color(0xFF00E5FF).withOpacity(0.25),
                          const Color(0xFF00E5FF).withOpacity(0),
                        ],
                      ),
                    ),
                  ),
                ],
                lineTouchData: LineTouchData(
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipItems: (touchedSpots) => touchedSpots.map((spot) => LineTooltipItem(
                          _formatCurrencyAmount(spot.y, currency),
                          GoogleFonts.poppins(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        )).toList(),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── TRADE ANALYSIS PREVIEW ──
  Widget _buildTradeAnalysisPreview() => GestureDetector(
      onTap: () {
        Navigator.push(context, MaterialPageRoute(builder: (_) => const TradeAnalysisScreen()));
      },
      child: _glassCard(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1B2838), Color(0xFF0D1B2A)],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [Color(0xFF00E5FF), Color(0xFF7C4DFF)]),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(Icons.analytics_outlined, color: Colors.white, size: 28),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'In-Depth Trade Analysis',
                    style: GoogleFonts.poppins(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Win rate, drawdown, risk score, symbol breakdown & more',
                    style: GoogleFonts.poppins(color: Colors.white54, fontSize: 11),
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios, color: Color(0xFF00E5FF), size: 18),
          ],
        ),
      ),
    );

  // ── TOP PAIRS ──
  Widget _buildTopPairsCard() {
    final selectedBots = _filteredBots();
    final currency = _preferredProfitCurrency();
    final symbolProfits = <String, double>{};
    for (final bot in selectedBots) {
      final symbols = bot['symbol'] ?? 'EURUSD';
      final profit = double.tryParse(bot['profit']?.toString() ?? '0') ?? 0;
      symbolProfits[symbols] = (symbolProfits[symbols] ?? 0) + profit;
    }
    final topPairs = symbolProfits.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final pairColors = [
      const Color(0xFF00E5FF),
      const Color(0xFF4CAF50),
      const Color(0xFFFFD600),
      const Color(0xFFFF5252),
      const Color(0xFF7C4DFF),
    ];

    return _glassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Top Performing Pairs',
              style: GoogleFonts.poppins(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600)),
          const SizedBox(height: 16),
          if (topPairs.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    const Icon(Icons.bar_chart, color: Colors.white24, size: 40),
                    const SizedBox(height: 8),
                    Text('No trading data yet', style: GoogleFonts.poppins(color: Colors.white38, fontSize: 13)),
                  ],
                ),
              ),
            )
          else
            ...topPairs.take(5).toList().asMap().entries.map((entry) {
              final i = entry.key;
              final pair = entry.value;
              final color = pairColors[i % pairColors.length];
              final maxVal = topPairs.first.value.abs();
              final barWidth = maxVal > 0 ? (pair.value.abs() / maxVal).clamp(0.05, 1.0) : 0.05;

              return Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Center(
                        child: Text(
                          '${i + 1}',
                          style: GoogleFonts.poppins(color: color, fontSize: 14, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(pair.key,
                              style: GoogleFonts.poppins(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500)),
                          const SizedBox(height: 4),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: barWidth.toDouble(),
                              backgroundColor: Colors.white10,
                              valueColor: AlwaysStoppedAnimation(pair.value >= 0 ? color : const Color(0xFFFF5252)),
                              minHeight: 6,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      _formatCurrencyAmount(pair.value, currency),
                      style: GoogleFonts.poppins(
                        color: pair.value >= 0 ? const Color(0xFF4CAF50) : const Color(0xFFFF5252),
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  // ── RECENT TRADES ──
  Widget _buildRecentTradesCard() {
    final tradingService = context.watch<TradingService>();
    final accountCurrency = tradingService.accountCurrency;
    final recentTrades = [...tradingService.closedTrades]
      ..sort((a, b) {
        final timeA = a.closedAt ?? a.openedAt;
        final timeB = b.closedAt ?? b.openedAt;
        return timeB.compareTo(timeA);
      });

    return _glassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Recent Trades',
                  style: GoogleFonts.poppins(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600)),
              GestureDetector(
                onTap: () => setState(() => _selectedIndex = 1),
                child: Text('View All',
                    style: GoogleFonts.poppins(color: const Color(0xFF00E5FF), fontSize: 12, fontWeight: FontWeight.w500)),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (recentTrades.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    const Icon(Icons.receipt_long, color: Colors.white24, size: 40),
                    const SizedBox(height: 8),
                    Text('No recent trades', style: GoogleFonts.poppins(color: Colors.white38, fontSize: 13)),
                  ],
                ),
              ),
            )
          else
            ...recentTrades.take(5).map((trade) {
              final profit = trade.profit ?? 0;
              final tradeCurrency = trade.currency.isNotEmpty ? trade.currency : accountCurrency;
              final direction = trade.type == TradeType.buy ? 'BUY' : 'SELL';
              final tradeTime = trade.closedAt ?? trade.openedAt;

              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.04),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: direction == 'BUY'
                            ? const Color(0xFF4CAF50).withOpacity(0.15)
                            : const Color(0xFFFF5252).withOpacity(0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        direction == 'BUY' ? Icons.arrow_upward : Icons.arrow_downward,
                        color: direction == 'BUY' ? const Color(0xFF4CAF50) : const Color(0xFFFF5252),
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            trade.symbol,
                            style: GoogleFonts.poppins(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
                          ),
                          Text(
                            '$direction  |  ${tradeTime.toLocal().toIso8601String().replaceFirst('T', ' ').split('.').first}',
                            style: GoogleFonts.poppins(color: Colors.white38, fontSize: 10),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      '${profit >= 0 ? "+" : ""}${_formatCurrencyAmount(profit, tradeCurrency)}',
                      style: GoogleFonts.poppins(
                        color: profit >= 0 ? const Color(0xFF4CAF50) : const Color(0xFFFF5252),
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  // ── QUICK ACTIONS GRID ──
  Widget _buildQuickActionsGrid() {
    final actions = [
      {
        'label': 'Create\nBot',
        'icon': Icons.add_circle,
        'color': const Color(0xFF00C853),
        'onTap': () => _pushScreen(const BotConfigurationRoute()),
      },
      {
        'label': 'Bot\nMonitor',
        'icon': Icons.trending_up,
        'color': const Color(0xFFFFB74D),
        'onTap': () => _pushScreen(const BotDashboardScreen()),
      },
      {
        'label': 'Trade\nAnalysis',
        'icon': Icons.analytics_outlined,
        'color': const Color(0xFF00E5FF),
        'onTap': () => _pushScreen(const TradeAnalysisScreen()),
      },
      {
        'label': 'Broker\nSetup',
        'icon': Icons.account_tree,
        'color': const Color(0xFF7C4DFF),
        'onTap': () => _pushScreen(const BrokerIntegrationScreen()),
      },
      {
        'label': 'Multi\nBroker',
        'icon': Icons.business_center,
        'color': const Color(0xFFB388FF),
        'onTap': () => _pushScreen(const MultiBrokerManagementScreen()),
      },
      {
        'label': 'Reports',
        'icon': Icons.assessment,
        'color': const Color(0xFFFF6E40),
        'onTap': () => _pushScreen(const ConsolidatedReportsScreen()),
      },
      {
        'label': 'Financials',
        'icon': Icons.attach_money,
        'color': const Color(0xFF26C6DA),
        'onTap': _openFinancials,
      },
      {
        'label': 'Commissions',
        'icon': Icons.monetization_on,
        'color': const Color(0xFF4CAF50),
        'onTap': () => _pushScreen(const CommissionDashboardScreen()),
      },
      {
        'label': 'Wallet',
        'icon': Icons.account_balance_wallet,
        'color': const Color(0xFFF0B90B),
        'onTap': () => _pushScreen(const UserWalletScreen()),
      },
      {
        'label': 'Portfolio',
        'icon': Icons.dashboard_customize,
        'color': const Color(0xFF5C6BC0),
        'onTap': () => _pushScreen(const UnifiedBrokerDashboardScreen()),
      },
      {
        'label': 'Broker\nIntel',
        'icon': Icons.speed,
        'color': const Color(0xFFFFD600),
        'onTap': () => _pushScreen(const BrokerAnalyticsDashboard()),
      },
      {
        'label': 'Referrals',
        'icon': Icons.group_add,
        'color': const Color(0xFF66BB6A),
        'onTap': _openReferralDashboard,
      },
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Mobile Command Center',
          style: GoogleFonts.poppins(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        Text(
          'Reports, wallet, commissions, analytics, and trading controls are all available here on mobile.',
          style: GoogleFonts.poppins(color: Colors.white54, fontSize: 11),
        ),
        const SizedBox(height: 14),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 1,
          ),
          itemCount: actions.length,
          itemBuilder: (context, index) {
            final action = actions[index];
            final label = action['label']! as String;
            final icon = action['icon']! as IconData;
            final color = action['color']! as Color;
            final onTap = action['onTap']! as VoidCallback;

            return InkWell(
              onTap: onTap,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      color.withOpacity(0.25),
                      color.withOpacity(0.08),
                    ],
                  ),
                  border: Border.all(color: color.withOpacity(0.3)),
                  boxShadow: [
                    BoxShadow(
                      color: color.withOpacity(0.15),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: color.withOpacity(0.2),
                      ),
                      child: Icon(
                        icon,
                        color: color,
                        size: 28,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      label,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.poppins(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E21),
      drawer: _buildDrawerMenu(loc),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A0E21),
        elevation: 0,
        title: Row(
          children: [
            const LogoWidget(size: 40, showText: false),
            const SizedBox(width: 12),
            Text(
              'ZWESTA',
              style: GoogleFonts.poppins(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
              ),
            ),
          ],
        ),
        actions: [
          const KillSwitchButton(),
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white70),
            onPressed: _fetchRealBots,
            tooltip: loc.translate('refresh_bots'),
          ),
        ],
      ),
      body: Column(
        children: [
          const KillSwitchBanner(),
          Consumer<FallbackStatusProvider>(
            builder: (context, fallback, _) {
              if (fallback.usingFallback) {
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  color: Colors.amber.shade800.withOpacity(0.3),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline, color: Colors.amber, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          fallback.fallbackReason ?? 'Viewing cached data.',
                          style: GoogleFonts.poppins(color: Colors.amber.shade200, fontSize: 11),
                        ),
                      ),
                      GestureDetector(
                        onTap: () => fallback.clearFallback(),
                        child: const Icon(Icons.close, color: Colors.amber, size: 16),
                      ),
                    ],
                  ),
                );
              }
              return const SizedBox.shrink();
            },
          ),
          Expanded(child: _getScreenForIndex(_selectedIndex)),
        ],
      ),
      bottomNavigationBar: _buildBottomNavigationBar(loc),
    );
  }

  BottomNavigationBar _buildBottomNavigationBar(AppLocalizations loc) => BottomNavigationBar(
      currentIndex: _selectedIndex,
      type: BottomNavigationBarType.fixed,
      backgroundColor: const Color(0xFF111633),
      selectedItemColor: const Color(0xFF00E5FF),
      unselectedItemColor: Colors.white38,
      selectedLabelStyle: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.w600),
      unselectedLabelStyle: GoogleFonts.poppins(fontSize: 10),
      items: const [
        BottomNavigationBarItem(icon: Icon(Icons.dashboard_rounded), label: 'Dashboard'),
        BottomNavigationBarItem(icon: Icon(Icons.swap_horiz_rounded), label: 'Trades'),
        BottomNavigationBarItem(icon: Icon(Icons.account_circle_rounded), label: 'Accounts'),
        BottomNavigationBarItem(icon: Icon(Icons.smart_toy_outlined), label: 'Bots'),
        BottomNavigationBarItem(icon: Icon(Icons.widgets_rounded), label: 'Hub'),
      ],
      onTap: (index) {
        setState(() {
          _selectedIndex = index;
        });
      },
    );

  Widget _buildDrawerMenu(AppLocalizations loc) => Drawer(
      backgroundColor: const Color(0xFF111633),
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          DrawerHeader(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF1A237E), Color(0xFF0D47A1)],
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [Color(0xFF00E5FF), Color(0xFF7C4DFF)]),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.auto_graph, color: Colors.white, size: 22),
                ),
                const SizedBox(height: 12),
                Text(
                  'ZWESTA TRADING',
                  style: GoogleFonts.poppins(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold, letterSpacing: 1),
                ),
                const SizedBox(height: 4),
                Text(
                  'Multi-Broker Auto-Trading System',
                  style: GoogleFonts.poppins(color: Colors.white60, fontSize: 12),
                ),
              ],
            ),
          ),
          ListTile(
            leading: const Icon(Icons.dashboard_rounded, color: Color(0xFF00E5FF)),
            title: const Text('Dashboard', style: TextStyle(color: Colors.white)),
            onTap: () {
              Navigator.pop(context);
              setState(() => _selectedIndex = 0);
            },
          ),
          ListTile(
            leading: const Icon(Icons.swap_horiz_rounded, color: Color(0xFF4CAF50)),
            title: const Text('Trades', style: TextStyle(color: Colors.white)),
            onTap: () {
              Navigator.pop(context);
              setState(() => _selectedIndex = 1);
            },
          ),
          ListTile(
            leading: const Icon(Icons.account_circle_rounded, color: Color(0xFFFFD600)),
            title: const Text('Accounts', style: TextStyle(color: Colors.white)),
            onTap: () {
              Navigator.pop(context);
              setState(() => _selectedIndex = 2);
            },
          ),
          ListTile(
            leading: const Icon(Icons.smart_toy_outlined, color: Color(0xFF7C4DFF)),
            title: const Text('Bots', style: TextStyle(color: Colors.white)),
            onTap: () {
              Navigator.pop(context);
              setState(() => _selectedIndex = 3);
            },
          ),
          ListTile(
            leading: const Icon(Icons.widgets_rounded, color: Color(0xFF00E5FF)),
            title: const Text('Feature Hub', style: TextStyle(color: Colors.white)),
            subtitle: const Text('All web-version modules in one place', style: TextStyle(color: Colors.white38, fontSize: 11)),
            onTap: () {
              Navigator.pop(context);
              setState(() => _selectedIndex = 4);
            },
          ),
          ListTile(
            leading: const Icon(Icons.add_circle_outline, color: Color(0xFF4CAF50)),
            title: const Text('Create New Bot', style: TextStyle(color: Colors.white)),
            subtitle: const Text('Strategies, symbols & risk setup', style: TextStyle(color: Colors.white38, fontSize: 11)),
            onTap: () {
              Navigator.pop(context);
              _pushScreen(const BotConfigurationRoute());
            },
          ),
          ListTile(
            leading: const Icon(Icons.insights, color: Color(0xFFFFD600)),
            title: const Text('Bot Monitor', style: TextStyle(color: Colors.white)),
            subtitle: const Text('View active bots & performance', style: TextStyle(color: Colors.white38, fontSize: 11)),
            onTap: () {
              Navigator.pop(context);
              setState(() => _selectedIndex = 3);
            },
          ),
          const Divider(color: Colors.white12),
          ListTile(
            leading: const Icon(Icons.card_giftcard, color: Colors.orangeAccent),
            title: const Text('Rentals & Features', style: TextStyle(color: Colors.white)),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const RentalsAndFeaturesScreen(),
                ),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.account_tree, color: Color(0xFF00E5FF)),
            title: const Text('Broker Integration', style: TextStyle(color: Colors.white)),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const BrokerIntegrationScreen(),
                ),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.people, color: Color(0xFF4CAF50)),
            title: const Text('Manage Accounts', style: TextStyle(color: Colors.white)),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const MultiAccountManagementScreen(),
                ),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.assessment, color: Color(0xFFFFD600)),
            title: const Text('Consolidated Reports', style: TextStyle(color: Colors.white)),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const ConsolidatedReportsScreen(),
                ),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.bar_chart, color: Color(0xFF00B0FF)),
            title: const Text('Financials', style: TextStyle(color: Colors.white)),
            onTap: () {
              Navigator.pop(context);
              final tradingService = context.read<TradingService>();
              if (tradingService.primaryAccount != null) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => FinancialsScreen(
                      account: tradingService.primaryAccount!,
                    ),
                  ),
                );
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('No account available'),
                  ),
                );
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.monetization_on, color: Color(0xFF4CAF50)),
            title: const Text('Commissions', style: TextStyle(color: Colors.white)),
            subtitle: const Text('Earnings, withdrawals & referral income', style: TextStyle(color: Colors.white38, fontSize: 11)),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(context, MaterialPageRoute(builder: (_) => const CommissionDashboardScreen()));
            },
          ),
          ListTile(
            leading: const Icon(Icons.speed, color: Color(0xFFFFD600)),
            title: const Text('Broker Analytics', style: TextStyle(color: Colors.white)),
            subtitle: const Text('Connection health & performance', style: TextStyle(color: Colors.white38, fontSize: 11)),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(context, MaterialPageRoute(builder: (_) => const BrokerAnalyticsDashboard()));
            },
          ),
          // IG Markets integration removed
          ListTile(
            leading: const Icon(Icons.account_balance_wallet, color: Color(0xFF7C4DFF)),
            title: const Text('FXCM Withdrawals', style: TextStyle(color: Colors.white)),
            subtitle: const Text('Auto-close & withdraw profits', style: TextStyle(color: Colors.white38, fontSize: 11)),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(context, MaterialPageRoute(builder: (_) => const FxcmWithdrawalScreen()));
            },
          ),
          ListTile(
            leading: const Icon(Icons.currency_bitcoin, color: Color(0xFFF0B90B)),
            title: const Text('Binance Withdrawals', style: TextStyle(color: Colors.white)),
            subtitle: const Text('Crypto profits & USDT withdrawal', style: TextStyle(color: Colors.white38, fontSize: 11)),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(context, MaterialPageRoute(builder: (_) => const BinanceWithdrawalScreen()));
            },
          ),
          ListTile(
            leading: const Icon(Icons.account_balance_wallet, color: Color(0xFF9C27B0)),
            title: const Text('My Wallet', style: TextStyle(color: Colors.white)),
            subtitle: const Text('View earned balance & pending withdrawals', style: TextStyle(color: Colors.white38, fontSize: 11)),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(context, MaterialPageRoute(builder: (_) => const UserWalletScreen()));
            },
          ),
          ListTile(
            leading: const Icon(Icons.admin_panel_settings, color: Color(0xFFE74C3C)),
            title: const Text('Admin: Verify Withdrawals', style: TextStyle(color: Colors.white)),
            subtitle: const Text('Verify broker withdrawals & split commission', style: TextStyle(color: Colors.white38, fontSize: 11)),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminWithdrawalVerificationScreen()));
            },
          ),
          const Divider(color: Colors.white12),
          ListTile(
            leading: const Icon(Icons.dashboard_customize, color: Color(0xFF00E5FF)),
            title: const Text('Unified Portfolio', style: TextStyle(color: Colors.white)),
            subtitle: const Text('All brokers in one view', style: TextStyle(color: Colors.white38, fontSize: 11)),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(context, MaterialPageRoute(builder: (_) => const UnifiedBrokerDashboardScreen()));
            },
          ),
          ListTile(
            leading: const Icon(Icons.smart_toy, color: Color(0xFFF0B90B)),
            title: const Text('Crypto Strategies', style: TextStyle(color: Colors.white)),
            subtitle: const Text('Grid, DCA, Scalper & more', style: TextStyle(color: Colors.white38, fontSize: 11)),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(context, MaterialPageRoute(builder: (_) => const CryptoStrategiesScreen()));
            },
          ),
          const Divider(color: Colors.white12),
          ListTile(
            leading: const Icon(Icons.group_add, color: Color(0xFF4CAF50)),
            title: const Text('My Referrals', style: TextStyle(color: Colors.white)),
            subtitle: const Text('Invite friends & earn 5%', style: TextStyle(color: Colors.white38, fontSize: 11)),
            onTap: () {
              Navigator.pop(context);
              final userId = context.read<AuthService>().currentUser?.id ?? '0';
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => ReferralDashboardScreen(userId: userId),
                ),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.admin_panel_settings, color: Color(0xFFFF5252)),
            title: const Text('Admin Dashboard', style: TextStyle(color: Colors.white)),
            subtitle: const Text('View all users & earnings', style: TextStyle(color: Colors.white38, fontSize: 11)),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const AdminDashboardScreen(),
                ),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.tune, color: Color(0xFFFF6E40)),
            title: const Text('Commission Config', style: TextStyle(color: Colors.white)),
            subtitle: const Text('Manage commission splits', style: TextStyle(color: Colors.white38, fontSize: 11)),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const CommissionConfigScreen(),
                ),
              );
            },
          ),
          const Divider(color: Colors.white12),
          ListTile(
            leading: const Icon(Icons.analytics_outlined, color: Color(0xFF00E5FF)),
            title: const Text('Trade Analysis', style: TextStyle(color: Colors.white)),
            subtitle: const Text('In-depth performance metrics', style: TextStyle(color: Colors.white38, fontSize: 11)),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const TradeAnalysisScreen(),
                ),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.analytics, color: Color(0xFF7C4DFF)),
            title: const Text('Trading Dashboard', style: TextStyle(color: Colors.white)),
            subtitle: const Text('Your stats & performance', style: TextStyle(color: Colors.white38, fontSize: 11)),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const EnhancedDashboardScreen(),
                ),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.business, color: Color(0xFF00E5FF)),
            title: const Text('Multi-Broker Management', style: TextStyle(color: Colors.white)),
            subtitle: const Text('Add/remove broker credentials', style: TextStyle(color: Colors.white38, fontSize: 11)),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const MultiBrokerManagementScreen(),
                ),
              );
            },
          ),
          const Divider(color: Colors.white12),
          ListTile(
            leading: const Icon(Icons.logout, color: Color(0xFFFF5252)),
            title: const Text('Logout', style: TextStyle(color: Color(0xFFFF5252))),
            onTap: () {
              context.read<AuthService>().logout();
              Navigator.pop(context);
            },
          ),
        ],
      ),
    );
}

class _FeatureAction {
  const _FeatureAction(this.label, this.icon, this.color, this.onTap);

  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
}

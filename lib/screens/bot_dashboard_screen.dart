// ignore_for_file: unused_element

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../providers/currency_provider.dart';
import '../services/bot_service.dart';
import '../services/broker_credentials_service.dart';
import '../services/financial_export_service.dart';
import '../services/risk_management_service.dart';
import '../services/trade_alert_service.dart';
import '../utils/environment_config.dart';
import '../widgets/account_display_widget.dart';
import '../widgets/logo_widget.dart';

import '../widgets/trading_mode_switcher.dart';
import 'bot_analytics_screen.dart';
import 'bot_configuration_route.dart';
import 'consolidated_reports_screen.dart';
import 'dashboard_screen.dart';

class BotDashboardScreen extends StatefulWidget {
  const BotDashboardScreen({Key? key, this.embedded = false}) : super(key: key);

  final bool embedded;

  @override
  State<BotDashboardScreen> createState() => _BotDashboardScreenState();
}

class _BotDashboardScreenState extends State<BotDashboardScreen> {
  String _searchQuery = '';
  String _filterStatus = 'all'; // 'all', 'active', 'inactive'
  String _tradingMode = 'DEMO'; // Current trading mode: DEMO or LIVE
  bool _showAccountDetails = false; // Toggle to show account details

  @override
  void initState() {
    super.initState();
    _loadTradingMode();
  }

  Future<void> _loadTradingMode() async {
    final prefs = await SharedPreferences.getInstance();
    final storedMode = (prefs.getString('trading_mode') ?? '').trim().toUpperCase();
    final fallbackMode = (prefs.getBool('is_live_mode') ?? false) ? 'LIVE' : 'DEMO';
    final mode = storedMode == 'LIVE' || storedMode == 'DEMO' ? storedMode : fallbackMode;
    setState(() => _tradingMode = mode);
    // Re-fetch bots with the correct mode
    if (mounted) {
      final botService = context.read<BotService>();
      botService.attachRiskService(context.read<RiskManagementService>());
      botService.attachAlertService(context.read<TradeAlertService>());
      botService.startPolling(tradingMode: mode);
      botService.fetchActiveBots(tradingMode: mode, force: true);
      botService.fetchActiveTrades();
    }
  }

  void _onModeChanged(String newMode) {
    setState(() => _tradingMode = newMode);
    // Re-fetch bots filtered by the new mode
    final botService = context.read<BotService>();
    botService.startPolling(tradingMode: newMode);
    botService.fetchActiveBots(tradingMode: newMode, force: true);
  }

  Future<void> _openBotConfigurationRoute(BotConfigurationRoute route) async {
    final updated = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => route),
    );
    if (updated == true && mounted) {
      await _loadTradingMode();
    }
  }

  @override
  void dispose() {
    context.read<BotService>().stopPolling();
    super.dispose();
  }

  String _currencySymbol(AppCurrency currency) {
    switch (currency) {
      case AppCurrency.usd:
        return r'$';
      case AppCurrency.zar:
        return 'R';
      case AppCurrency.gbp:
        return 'GBP';
    }
  }

  String _currencyCode(AppCurrency currency) {
    switch (currency) {
      case AppCurrency.usd:
        return 'USD';
      case AppCurrency.zar:
        return 'ZAR';
      case AppCurrency.gbp:
        return 'GBP';
    }
  }

  String _normalizeCurrencyCode(dynamic value) {
    final currency = value?.toString().trim().toUpperCase();
    return currency == null || currency.isEmpty ? 'USD' : currency;
  }

  bool _isLiveBot(Map<String, dynamic> bot) {
    final mode = bot['mode']?.toString().trim().toLowerCase();
    if (mode == 'live' || mode == 'real') {
      return true;
    }
    return bot['is_live'] == true;
  }

  bool _isActiveBot(Map<String, dynamic> bot) {
    if (bot['enabled'] == true) {
      return true;
    }
    final status = (bot['status'] ?? '').toString().trim().toUpperCase();
    return status == 'ACTIVE' || status == 'STARTING' || status == 'RUNNING';
  }

  /// Classifies bots by broker. Returns 'Binance' / 'Exness' / 'FXCM' / 'Other'.
  String _brokerKey(Map<String, dynamic> bot) {
    final candidates = [
      bot['broker'],
      bot['brokerName'],
      bot['broker_type'],
      bot['brokerType'],
      bot['broker_account_id'],
      bot['accountNumber'],
    ];
    for (final raw in candidates) {
      final s = raw?.toString().toLowerCase() ?? '';
      if (s.isEmpty) continue;
      if (s.contains('binance')) return 'Binance';
      if (s.contains('exness') || s.startsWith('mt5_') || s.startsWith('exness_')) return 'Exness';
      if (s.contains('fxcm')) return 'FXCM';
    }
    return 'Other';
  }

  Color _brokerAccent(String brokerKey) {
    switch (brokerKey) {
      case 'Binance':
        return const Color(0xFFF3BA2F);
      case 'Exness':
        return const Color(0xFF00E5FF);
      case 'FXCM':
        return const Color(0xFF7C4DFF);
      default:
        return Colors.white70;
    }
  }

  String _brokerIconChar(String brokerKey) {
    switch (brokerKey) {
      case 'Binance':
        return '₿';
      case 'Exness':
        return 'E';
      case 'FXCM':
        return 'F';
      default:
        return '•';
    }
  }

  /// Extracts the quote asset (the currency profit is denominated in) from a
  /// Binance trading symbol. Examples:
  ///   BTCUSDT -> USDT, ETHUSDC -> USDC, SOLFDUSD -> FDUSD,
  ///   BNBBTC  -> BTC,  ADAETH -> ETH,  SOLUSDT -> USDT.
  /// Returns null if it cannot confidently identify the quote asset.
  String? _binanceQuoteFromSymbol(String? symbolRaw) {
    if (symbolRaw == null) return null;
    final s = symbolRaw.toString().toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    if (s.isEmpty) return null;
    // Order matters: longest suffixes first so 'FDUSD' wins over 'USD'.
    const quotes = [
      'FDUSD', 'TUSD', 'BUSD', 'USDT', 'USDC', 'DAI',
      'USD', 'EUR', 'GBP', 'TRY', 'ZAR', 'AUD', 'BRL',
      'BTC', 'ETH', 'BNB', 'SOL', 'XRP',
    ];
    for (final q in quotes) {
      if (s.endsWith(q) && s.length > q.length) return q;
    }
    return null;
  }

  /// First trading symbol on the bot (used for Binance currency inference).
  String? _firstSymbol(Map<String, dynamic> bot) {
    final raw = bot['symbol'] ?? bot['symbols'];
    if (raw == null) return null;
    if (raw is List && raw.isNotEmpty) return raw.first?.toString();
    final str = raw.toString();
    if (str.isEmpty || str.toLowerCase() == 'n/a') return null;
    // Allow "BTCUSDT, ETHUSDT" or "BTCUSDT|ETHUSDT".
    final parts = str.split(RegExp(r'[,\s|/;]+')).where((p) => p.isNotEmpty).toList();
    return parts.isEmpty ? str : parts.first;
  }

  String _botDisplayCurrency(Map<String, dynamic> bot) {
    final brokerKey = _brokerKey(bot);

    // Binance: profit is denominated in the symbol's quote asset
    // (USDT / USDC / BTC / SOL / etc.). Always derive from symbol when possible
    // — this beats any stale displayCurrency the backend might have stamped.
    if (brokerKey == 'Binance') {
      final quote = _binanceQuoteFromSymbol(_firstSymbol(bot));
      if (quote != null) return quote;
      // Fallback: explicit field, else USDT.
      final raw = bot['displayCurrency'] ?? bot['accountCurrency'] ?? bot['currency'];
      if (raw != null && raw.toString().trim().isNotEmpty) {
        return _normalizeCurrencyCode(raw);
      }
      return 'USDT';
    }

    // Exness / FXCM / Other: use explicit field if set, else infer.
    final raw = bot['displayCurrency'] ?? bot['accountCurrency'] ?? bot['currency'];
    if (raw != null && raw.toString().trim().isNotEmpty) {
      return _normalizeCurrencyCode(raw);
    }
    switch (brokerKey) {
      case 'FXCM':
        return 'USD';
      case 'Exness':
        return _isLiveBot(bot) ? 'ZAR' : 'USD';
      default:
        return _isLiveBot(bot) ? 'ZAR' : 'USD';
    }
  }

  String _symbolForCode(String currencyCode) {
    final code = _normalizeCurrencyCode(currencyCode);
    switch (code) {
      case 'ZAR':
        return 'R';
      case 'GBP':
        return 'GBP';
      case 'EUR':
        return '€';
      case 'USD':
        return r'$';
      default:
        // For crypto / unknown fiat: show the code as a prefix (e.g. "USDT 12.34",
        // "BTC 0.0012", "SOL 1.42"). Keeps formatting unambiguous.
        return '$code ';
    }
  }

  String _formatAmount(
    CurrencyProvider currencyProvider,
    double amount, {
    int decimals = 2,
    String? currencyCode,
  }) {
    final code = _normalizeCurrencyCode(currencyCode ?? _currencyCode(currencyProvider.currency));
    final symbol = _symbolForCode(code);
    // Crypto quote assets need more precision for small balances.
    int effDecimals = decimals;
    if (code == 'BTC' || code == 'ETH') {
      effDecimals = decimals < 6 ? 6 : decimals;
    } else if (code == 'BNB' || code == 'SOL' || code == 'XRP') {
      effDecimals = decimals < 4 ? 4 : decimals;
    }
    final absoluteAmount = amount.abs().toStringAsFixed(effDecimals);
    if (amount < 0) {
      return '-$symbol$absoluteAmount';
    }
    return '$symbol$absoluteAmount';
  }

  String _formatPositionSize(
    double quantity, {
    required bool isBinance,
  }) {
    if (isBinance) {
      final decimals = quantity >= 1 ? 3 : (quantity >= 0.1 ? 4 : 6);
      return '${quantity.toStringAsFixed(decimals)} qty';
    }
    return '${quantity.toStringAsFixed(2)} lots';
  }

  String _formatProfileLabel(String? profile) {
    switch ((profile ?? '').trim().toLowerCase()) {
      case 'beginner':
        return 'Beginner';
      case 'balanced':
        return 'Balanced';
      case 'advanced':
        return 'Advanced';
      case 'fast_growth':
        return 'Quick Profit';
      case 'small_account':
        return 'Small Account';
      default:
        final value = (profile ?? '').trim();
        if (value.isEmpty) {
          return 'Balanced';
        }
        return value
            .split('_')
            .where((part) => part.isNotEmpty)
            .map((part) => part[0].toUpperCase() + part.substring(1))
            .join(' ');
    }
  }

  String _normalizeBrokerLabel(dynamic value) {
    final raw = (value ?? '').toString().trim();
    if (raw.isEmpty) {
      return 'MT5';
    }

    switch (raw.toLowerCase()) {
      case 'fxm':
      case 'fxcm':
        return 'FXCM';
      case 'binance':
        return 'Binance';
      case 'exness':
        return 'Exness';
      case 'mt5':
        return 'MT5';
      default:
        return raw
            .split(RegExp(r'[\s_-]+'))
            .where((part) => part.isNotEmpty)
            .map((part) => part[0].toUpperCase() + part.substring(1).toLowerCase())
            .join(' ');
    }
  }

  Color _brokerAccentColor(String brokerLabel) {
    switch (brokerLabel.toLowerCase()) {
      case 'binance':
        return const Color(0xFFF7931A);
      case 'fxcm':
        return const Color(0xFF26C6DA);
      case 'exness':
        return const Color(0xFF42A5F5);
      default:
        return const Color(0xFF2196F3);
    }
  }

  String _botConnectionLabel(Map<String, dynamic> bot) {
    final brokerLabel = _normalizeBrokerLabel(
      bot['brokerName'] ?? bot['broker_type'] ?? bot['broker'],
    );
    final accountNumber = (bot['accountNumber'] ?? bot['account_number'] ?? '')
        .toString()
        .trim();
    final symbol = (bot['symbol'] ?? '').toString().trim().toUpperCase();

    if (symbol.isNotEmpty && symbol != 'MULTI' && symbol != 'N/A') {
      return '${brokerLabel.toUpperCase()} • $symbol';
    }
    if (accountNumber.isNotEmpty) {
      return '${brokerLabel.toUpperCase()} • $accountNumber';
    }
    return brokerLabel.toUpperCase();
  }

  Widget _buildMetaChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.32)),
      ),
      child: Text(
        label,
        style: GoogleFonts.poppins(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildPromotionChip(Map<String, dynamic> bot) {
    final status = (bot['promotionStatus'] ?? '').toString().trim().toLowerCase();
    final remainingMinutes = int.tryParse(bot['promotionTimeRemainingMinutes']?.toString() ?? '');

    if (status.isEmpty || status == 'not_applicable') {
      return const SizedBox.shrink();
    }

    late final Color color;
    late final String label;
    switch (status) {
      case 'ready':
        color = Colors.green;
        label = 'Ready For Live';
        break;
      case 'expired':
        color = Colors.white54;
        label = 'Promotion Expired';
        break;
      default:
        color = Colors.orange;
        if (remainingMinutes != null && remainingMinutes > 0) {
          final hours = remainingMinutes ~/ 60;
          final minutes = remainingMinutes % 60;
          final timeText = hours > 0 ? '${hours}h ${minutes}m left' : '${minutes}m left';
          label = 'Evaluating • $timeText';
        } else {
          label = 'Evaluating';
        }
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.circle, color: color, size: 9),
          const SizedBox(width: 6),
          Text(
            label,
            style: GoogleFonts.poppins(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAdaptationChip(Map<String, dynamic> bot) {
    final adaptationEnabled = bot['autoAdaptationEnabled'] != false;
    final lastAdaptationReason = (bot['lastAdaptationReason'] ?? '').toString().trim();
    final lastAdaptationAtRaw = (bot['lastAdaptationAt'] ?? '').toString().trim();
    final lastAdaptationAt =
        lastAdaptationAtRaw.isEmpty ? null : DateTime.tryParse(lastAdaptationAtRaw);

    if (!adaptationEnabled) {
      return _buildMetaChip('Adapt: Off', Colors.white54);
    }

    var label = 'Adapt: On';
    if (lastAdaptationAt != null) {
      label = 'Adapted ${DateFormat('HH:mm').format(lastAdaptationAt.toLocal())}';
    }
    if (lastAdaptationReason.isNotEmpty) {
      final normalizedReason = lastAdaptationReason
          .replaceAll('; ', ' | ')
          .replaceAll('recent form', 'form');
      label = '$label • $normalizedReason';
    }

    return _buildMetaChip(label, Theme.of(context).colorScheme.primary);
  }

  double _botAmount(Map<String, dynamic> bot, List<String> fields) {
    for (final field in fields) {
      final raw = bot[field];
      if (raw == null) continue;
      final parsed = double.tryParse(raw.toString());
      if (parsed != null) return parsed;
    }
    return 0.0;
  }

  String _formatBotAggregate(
    CurrencyProvider currencyProvider,
    List<Map<String, dynamic>> bots,
    String field, {
    int decimals = 2,
    List<String> fallbackFields = const [],
  }) {
    final totals = <String, double>{};
    for (final bot in bots) {
      final currency = _botDisplayCurrency(bot);
      final amount = _botAmount(bot, [field, ...fallbackFields]);
      totals[currency] = (totals[currency] ?? 0.0) + amount;
    }
    if (totals.isEmpty) {
      return _formatAmount(currencyProvider, 0, decimals: decimals);
    }
    final entries = totals.entries.toList()..sort((a, b) => a.key.compareTo(b.key));
    return entries
        .map((entry) => _formatAmount(currencyProvider, entry.value, decimals: decimals, currencyCode: entry.key))
        .join(' • ');
  }

  @override
  Widget build(BuildContext context) {
    final content = Consumer2<BotService, CurrencyProvider>(
      builder: (context, botService, currencyProvider, _) {
        final allBots = List<Map<String, dynamic>>.from(botService.activeBots);

        // Apply search + status + mode filter
        final bots = allBots.where((bot) {
          final botId = (bot['botId'] ?? '').toString().toLowerCase();
          final symbol = (bot['symbol'] ?? bot['symbols'] ?? '').toString().toLowerCase();
          final strategy = (bot['strategy'] ?? '').toString().toLowerCase();
          final matchesSearch = _searchQuery.isEmpty ||
              botId.contains(_searchQuery.toLowerCase()) ||
              symbol.contains(_searchQuery.toLowerCase()) ||
              strategy.contains(_searchQuery.toLowerCase());
          final isEnabled = bot['enabled'] == true ||
              (bot['status'] ?? '').toString().toUpperCase() == 'ACTIVE';
          final matchesFilter = _filterStatus == 'all' ||
              (_filterStatus == 'active' && isEnabled) ||
              (_filterStatus == 'inactive' && !isEnabled);
          // NOTE: Previously bots were hidden unless their own is_live flag
          // matched the app's global trading_mode switcher. Now that the backend
          // returns both demo and live bots (mode=ALL), we keep ALL active bots
          // visible and rely on the per-card LIVE/DEMO badge to distinguish them.
          // The global switcher still re-fetches, but it no longer hides the other
          // mode's bots — so a LIVE bot stays visible while the app is in DEMO.
          final matchesMode = true;
          return matchesSearch && matchesFilter && matchesMode;
        }).toList();

        // Top 5 newest bots (by creation time or just last 5)
        final newestBots = List<Map<String, dynamic>>.from(allBots);
        newestBots.sort((a, b) {
          final aTime = a['createdAt']?.toString() ?? a['created_at']?.toString() ?? '';
          final bTime = b['createdAt']?.toString() ?? b['created_at']?.toString() ?? '';
          return bTime.compareTo(aTime);
        });

        final activeBots = bots.where(_isActiveBot).length;
        final totalProfit = bots.fold<double>(
          0,
          (sum, b) => sum + _botAmount(b, ['allTimeProfit', 'totalProfit', 'profit']),
        );

        return Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Theme.of(context).colorScheme.background,
                Theme.of(context).colorScheme.surface,
                Theme.of(context).colorScheme.background
              ],
            ),
          ),
          child: allBots.isEmpty && botService.isLoading
              ? Center(child: CircularProgressIndicator(color: Theme.of(context).colorScheme.primary))
              : allBots.isEmpty && !botService.isLoading
                  ? _buildNoBotsState()
              : RefreshIndicator(
                  onRefresh: () => botService.fetchActiveBots(tradingMode: _tradingMode, force: true),
                  color: Theme.of(context).colorScheme.primary,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    children: [
                      // ⭐ TRADING MODE SWITCHER & ACCOUNT DISPLAY
                      Theme(
                        data: Theme.of(context).copyWith(
                          cardColor: Colors.white.withOpacity(0.06),
                          primaryColor: Theme.of(context).colorScheme.primary,
                        ),
                        child: Column(
                          children: [
                            // Mode Switcher (Compact pill style)
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  'Account Mode',
                                  style: TextStyle(
                                    color: Colors.white70,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                TradingModeSwitcher(
                                  currentMode: _tradingMode,
                                  onModeChanged: _onModeChanged,
                                  isCompact: true,
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),

                            // Account Details Toggle & Display
                            if (_showAccountDetails)
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.04),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: Colors.white.withOpacity(0.08),
                                  ),
                                ),
                                child: AccountDisplayWidget(
                                  tradingMode: _tradingMode,
                                  onRefresh: () {
                                    context.read<BotService>().fetchActiveBots(tradingMode: _tradingMode, force: true);
                                  },
                                ),
                              )
                            else
                              Center(
                                child: TextButton.icon(
                                  onPressed: () =>
                                      setState(() => _showAccountDetails = true),
                                  icon: Icon(Icons.account_balance_wallet,
                                      size: 20, color: Theme.of(context).colorScheme.primary),
                                  label: Text(
                                    'Show Account Details',
                                    style: TextStyle(
                                      color: Theme.of(context).colorScheme.primary,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                              ),
                            const SizedBox(height: 16),
                          ],
                        ),
                      ),


                      // Summary row
                      Row(
                        children: [
                          _summaryChip(Icons.smart_toy, '$activeBots Active', Colors.green),
                          const SizedBox(width: 10),
                          _summaryChip(Icons.list_alt, '${allBots.length} Total', Theme.of(context).colorScheme.primary),
                          const SizedBox(width: 10),
                          _summaryChip(
                            totalProfit >= 0 ? Icons.trending_up : Icons.trending_down,
                            _formatBotAggregate(
                              currencyProvider,
                              allBots,
                              'allTimeProfit',
                              fallbackFields: ['totalProfit', 'profit'],
                            ),
                            totalProfit >= 0 ? Colors.green : Theme.of(context).colorScheme.secondary,
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerRight,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.06),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.white.withOpacity(0.08)),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<AppCurrency>(
                              value: currencyProvider.currency,
                              dropdownColor: const Color(0xFF1A1F3A),
                              iconEnabledColor: const Color(0xFF00E5FF),
                              style: GoogleFonts.poppins(color: Colors.white, fontSize: 12),
                              items: AppCurrency.values.map((currency) => DropdownMenuItem<AppCurrency>(
                                  value: currency,
                                  child: Text(_currencyCode(currency)),
                                )).toList(),
                              onChanged: (value) {
                                if (value != null) {
                                  currencyProvider.setCurrency(value);
                                }
                              },
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Search bar
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.06),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.white.withOpacity(0.08)),
                        ),
                        child: TextField(
                          onChanged: (v) => setState(() => _searchQuery = v),
                          style: GoogleFonts.poppins(color: Colors.white, fontSize: 14),
                          decoration: InputDecoration(
                            hintText: 'Search bots by name, symbol, strategy...',
                            hintStyle: GoogleFonts.poppins(color: Colors.white24, fontSize: 13),
                            prefixIcon: const Icon(Icons.search, color: Color(0xFF00E5FF), size: 20),
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Filter chips
                      Row(
                        children: [
                          _filterChip('All', 'all'),
                          const SizedBox(width: 8),
                          _filterChip('Active', 'active'),
                          const SizedBox(width: 8),
                          _filterChip('Inactive', 'inactive'),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Bots grouped by broker (Binance / Exness / etc.)
                      if (bots.isEmpty && !botService.isLoading)
                        _emptyState()
                      else if (botService.errorMessage != null && bots.isEmpty)
                        _errorState(botService.errorMessage!)
                      else
                        ..._buildBrokerSections(bots, currencyProvider),
                      GestureDetector(
                        onTap: () => _openBotConfigurationRoute(const BotConfigurationRoute()),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF00E5FF), Color(0xFF7C4DFF)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF00E5FF).withOpacity(0.3),
                                blurRadius: 16,
                                offset: const Offset(0, 6),
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.add_circle_outline, color: Colors.white, size: 22),
                              const SizedBox(width: 10),
                              Text('Create New Bot', style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15, letterSpacing: 0.3)),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),

                      GestureDetector(
                        onTap: () => _openBotConfigurationRoute(
                          const BotConfigurationRoute(
                            focusTestedTemplates: true,
                          ),
                        ),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF3BA2F).withOpacity(0.12),
                            border: Border.all(color: const Color(0xFFF3BA2F), width: 1.6),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.auto_awesome, color: Color(0xFFF3BA2F), size: 22),
                              const SizedBox(width: 10),
                              Text(
                                'Use Tested Binance Template',
                                style: GoogleFonts.poppins(
                                  color: const Color(0xFFF3BA2F),
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                  letterSpacing: 0.2,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),

                      // ⭐ BINANCE QUICK BOT - One-Click Creation
                      GestureDetector(
                        onTap: () {
                          // Show presets dialog or create directly
                          _showBinanceQuickCreateDialog(context);
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF3BA2F).withOpacity(0.15),
                            border: Border.all(color: const Color(0xFFF3BA2F), width: 2),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Text('₿ ', style: TextStyle(fontSize: 22)),
                              const SizedBox(width: 8),
                              Text(
                                'Quick Binance Bot',
                                style: GoogleFonts.poppins(
                                  color: const Color(0xFFF3BA2F),
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(width: 8),
                              const Icon(Icons.flash_on, color: Color(0xFFF3BA2F), size: 18),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Quick Action Links for Popular Brokers
                      Text(
                        'Quick Create',
                        style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white70),
                      ),
                      const SizedBox(height: 8),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            // Binance Quick Creator
                            _quickBrokerButton(
                              icon: '₿',
                              label: 'Binance',
                              color: const Color(0xFFF3BA2F),
                              onTap: () => _createBotForBroker(context, 'Binance'),
                              description: 'Crypto pairs',
                            ),
                            const SizedBox(width: 10),
                            // Commodities Quick Creator
                            _quickBrokerButton(
                              icon: Icons.trending_up,
                              label: 'Commodities',
                              color: const Color(0xFFFF9800),
                              onTap: () => _createBotForBroker(context, 'Exness'),
                              description: 'Gold, Oil...',
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
        );
      },
    );

    if (widget.embedded) {
      return content;
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0A0E21),
      appBar: AppBar(
        backgroundColor: const Color(0xFF111633),
        elevation: 0,
        title: const Row(
          children: [
            LogoWidget(size: 36, showText: false),
            SizedBox(width: 10),
            Text('Bot Monitor'),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Reports',
            icon: const Icon(Icons.assessment_outlined),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ConsolidatedReportsScreen()),
              );
            },
          ),
          IconButton(
            tooltip: 'Dashboard',
            icon: const Icon(Icons.dashboard_rounded),
            onPressed: () {
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (_) => const DashboardScreen()),
                (route) => route.isFirst,
              );
            },
          ),
        ],
      ),
      body: content,
    );
  }

  Widget _summaryChip(IconData icon, String label, Color color) => Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.06),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withOpacity(0.08)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 16),
            const SizedBox(width: 6),
            Flexible(
              child: Text(label, style: GoogleFonts.poppins(color: color, fontSize: 12, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
      ),
    );

  Widget _emptyState() => Container(
      padding: const EdgeInsets.all(40),
      child: Column(
        children: [
          Icon(Icons.smart_toy_outlined, color: Colors.white.withOpacity(0.2), size: 64),
          const SizedBox(height: 16),
          Text('No bots created yet', style: GoogleFonts.poppins(color: Colors.white54, fontSize: 16)),
          const SizedBox(height: 8),
          Text('Tap "Create New Bot" to get started', style: GoogleFonts.poppins(color: Colors.white30, fontSize: 13)),
        ],
      ),
    );

  Widget _errorState(String error) => Container(
      padding: const EdgeInsets.all(24),
      margin: const EdgeInsets.only(top: 12),
      decoration: BoxDecoration(
        color: Colors.red.withOpacity(0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.red.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          const Icon(Icons.error_outline, color: Colors.redAccent, size: 36),
          const SizedBox(height: 12),
          Text(error, style: GoogleFonts.poppins(color: Colors.redAccent, fontSize: 13), textAlign: TextAlign.center),
          const SizedBox(height: 12),
          TextButton(
            onPressed: () => context.read<BotService>().fetchActiveBots(tradingMode: _tradingMode, force: true),
            child: Text('Retry', style: GoogleFonts.poppins(color: const Color(0xFF00E5FF))),
          ),
        ],
      ),
    );

  Widget _buildBotCard(Map<String, dynamic> bot, CurrencyProvider currencyProvider) => _buildUnifiedBotCard(bot, currencyProvider);

  Widget _buildNoBotsState() => Center(
        child: Padding(
          padding: const EdgeInsets.all(48),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.smart_toy_outlined, size: 64, color: Colors.white.withOpacity(0.2)),
              const SizedBox(height: 16),
              Text(
                'No Active Bots',
                style: GoogleFonts.poppins(
                  color: Colors.white70,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Create a bot to start trading automatically',
                style: GoogleFonts.poppins(
                  color: Colors.white54,
                  fontSize: 14,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );

  /// Groups bots by broker (Binance / Exness / FXCM / Other) and renders
  /// each non-empty group with a header showing count + native-currency P&L.
  List<Widget> _buildBrokerSections(
    List<Map<String, dynamic>> botsList,
    CurrencyProvider currencyProvider,
  ) {
    if (botsList.isEmpty) return const [];
    final grouped = <String, List<Map<String, dynamic>>>{
      'Binance': [],
      'Exness': [],
      'FXCM': [],
      'Other': [],
    };
    for (final bot in botsList) {
      grouped[_brokerKey(bot)]!.add(bot);
    }
    final out = <Widget>[];
    for (final key in const ['Binance', 'Exness', 'FXCM', 'Other']) {
      final group = grouped[key]!;
      if (group.isEmpty) continue;
      out.add(_brokerSectionHeader(key, group, currencyProvider));
      out.addAll(group.map((b) => _buildBotCard(b, currencyProvider)));
      out.add(const SizedBox(height: 8));
    }
    return out;
  }

  Widget _brokerSectionHeader(
    String brokerKey,
    List<Map<String, dynamic>> group,
    CurrencyProvider currencyProvider,
  ) {
    final accent = _brokerAccent(brokerKey);
    final count = group.length;
    final activeCount = group
        .where((b) => b['enabled'] == true || b['status'] == 'Active')
        .length;
    // Aggregate profit per native currency code (Binance bots in USDT, Exness
    // live bots in ZAR, etc.). Show each currency total separately.
    final byCurrency = <String, double>{};
    for (final b in group) {
      final code = _botDisplayCurrency(b);
      final p = _botAmount(b, ['allTimeProfit', 'totalProfit', 'profit']);
      byCurrency[code] = (byCurrency[code] ?? 0) + p;
    }
    final totalsText = byCurrency.entries
        .map((e) => _formatAmount(currencyProvider, e.value, currencyCode: e.key))
        .join(' • ');

    return Container(
      margin: const EdgeInsets.only(top: 8, bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: accent.withOpacity(0.08),
        border: Border.all(color: accent.withOpacity(0.35)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: accent.withOpacity(0.18),
              shape: BoxShape.circle,
              border: Border.all(color: accent),
            ),
            child: Text(
              _brokerIconChar(brokerKey),
              style: TextStyle(
                color: accent,
                fontWeight: FontWeight.w800,
                fontSize: 14,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  brokerKey == 'Other' ? 'Other Brokers' : brokerKey,
                  style: GoogleFonts.poppins(
                    color: accent,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    letterSpacing: 0.3,
                  ),
                ),
                Text(
                  '$activeCount active • $count bot${count == 1 ? '' : 's'} • all-time P/L',
                  style: GoogleFonts.poppins(
                    color: Colors.white60,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          if (totalsText.isNotEmpty)
            Flexible(
              child: Text(
                totalsText,
                textAlign: TextAlign.right,
                style: GoogleFonts.poppins(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildUnifiedBotCard(Map<String, dynamic> bot, CurrencyProvider currencyProvider) {
    final botId = bot['botId'] ?? 'Unknown';
    final isEnabled = bot['enabled'] == true || bot['status'] == 'Active';
    final botMode = (bot['mode'] ?? '').toString().trim().toLowerCase();
    final isDemoBot = botMode == 'demo' || (botMode.isEmpty && bot['is_live'] != true);
    final status = (bot['status'] ?? (isEnabled ? 'Active' : 'Inactive')).toString().toUpperCase();
    final sessionProfit = _botAmount(bot, ['sessionProfit', 'currentProfit', 'profit']);
    final allTimeProfit = _botAmount(bot, ['allTimeProfit', 'totalProfit', 'lifetimeCurrentProfit', 'profit']);
    final totalTrades = int.tryParse(bot['totalTrades']?.toString() ?? '0') ?? 0;
    final winRate = double.tryParse(bot['winRate']?.toString() ?? '0') ?? 0;
    final roi = double.tryParse(bot['roi']?.toString() ?? '0') ?? 0;
    final avgTrade = double.tryParse(bot['avgProfitPerTrade']?.toString() ?? '0') ?? 0;
    final maxDrawdown = double.tryParse(bot['maxDrawdown']?.toString() ?? '0') ?? 0;
    final todayClosedProfit = double.tryParse(bot['dailyProfit']?.toString() ?? '0') ?? 0;
    final openPositions = (bot['openPositionsPreview'] as List?) ?? (bot['openPositions'] as List?) ?? [];
    final floatingProfit = double.tryParse(bot['floatingProfit']?.toString() ?? '0') ??
      openPositions.fold<double>(0, (sum, position) => sum + (double.tryParse(position['profit']?.toString() ?? '0') ?? 0));
    final currentProfit = sessionProfit;
    final promotionStatus = (bot['promotionStatus'] ?? '').toString().trim().toLowerCase();
    final isPromotionEligible = isDemoBot && (bot['promotionEligible'] == true || promotionStatus == 'ready');
    final accountBalance = double.tryParse(bot['accountBalance']?.toString() ?? '0') ?? 0;
    final accountEquity = double.tryParse(bot['accountEquity']?.toString() ?? '0') ?? 0;
    final tradeAmount = double.tryParse(bot['tradeAmount']?.toString() ?? '0') ?? 0;
    final effectiveTradeAmount = double.tryParse(bot['effectiveTradeAmount']?.toString() ?? '0') ?? 0;
    final double configuredCapital = effectiveTradeAmount > 0
      ? effectiveTradeAmount
      : (tradeAmount > 0 ? tradeAmount : 0.0);
    final investedCapital = double.tryParse(bot['roiBasis']?.toString() ?? '0') ??
      double.tryParse(bot['totalInvestment']?.toString() ?? '0') ??
      0;
    final openPositionsCount = int.tryParse(bot['openPositionsCount']?.toString() ?? '${openPositions.length}') ?? openPositions.length;
    final visibleTradeCount = totalTrades > 0 ? totalTrades : openPositionsCount;
    final symbols = bot['symbol'] ?? bot['symbols'] ?? 'N/A';
    final strategy = bot['strategy'] ?? 'Auto';
    final brokerType = bot['broker_type'] ?? bot['broker'] ?? 'MT5';
    final brokerLabel = _botConnectionLabel(bot);
    final isBinanceBot = _normalizeBrokerLabel(bot['brokerName'] ?? brokerType).toLowerCase() == 'binance';
    final isMicroAccount = isBinanceBot && !isDemoBot && accountBalance > 0 && accountBalance < 20.0;
    final brokerAccent = _brokerAccentColor(_normalizeBrokerLabel(bot['brokerName'] ?? brokerType));
    final displayCurrency = _botDisplayCurrency(bot);
    final presetName = (bot['presetName'] ?? '').toString().trim();
    final profileLabel = _formatProfileLabel(bot['managementProfile']?.toString());
    final accountModeLabel = isDemoBot ? 'DEMO' : 'LIVE';
    final symbolStr = symbols is List ? symbols.join(', ') : symbols.toString();
    final runtime = bot['runtimeFormatted'] ?? '--';
    final createdAt = bot['createdAt'] ?? '';
    final isNewBot = createdAt.isNotEmpty && DateTime.tryParse(createdAt) != null && DateTime.now().difference(DateTime.tryParse(createdAt)!).inHours < 24;
    final pauseReason = (bot['pauseReason'] ?? '').toString().trim();
    final lastNoTradeReason = (bot['lastNoTradeReason'] ?? '').toString().trim();
    final lastNoTradeAtText = (bot['lastNoTradeAt'] ?? '').toString().trim();
    final lastNoTradeAt = lastNoTradeAtText.isEmpty ? null : DateTime.tryParse(lastNoTradeAtText);
    final hasRecentNoTradeReason =
      lastNoTradeReason.isNotEmpty &&
      lastNoTradeAt != null &&
      DateTime.now().difference(lastNoTradeAt.toLocal()).inMinutes <= 15;
    final idleReason = pauseReason.isNotEmpty
      ? pauseReason
      : (hasRecentNoTradeReason ? lastNoTradeReason : '');
    final drawdownPauseUntilText = bot['drawdownPauseUntil']?.toString();
    final drawdownPauseUntil = drawdownPauseUntilText == null || drawdownPauseUntilText.isEmpty
      ? null
      : DateTime.tryParse(drawdownPauseUntilText);
    final isCoolingDown = drawdownPauseUntil != null && drawdownPauseUntil.isAfter(DateTime.now());
    final activeSymbolCooldowns = (bot['activeSymbolCooldowns'] as List?) ?? [];
    final temporalGuardStatus = (bot['temporalGuardStatus'] ?? 'normal').toString().trim().toLowerCase();
    final temporalGuardHeadline = (bot['temporalGuardHeadline'] ?? '').toString().trim();
    final temporalGuardReason = (bot['temporalGuardReason'] ?? '').toString().trim();
    final showTemporalGuard = temporalGuardStatus == 'blocked' || temporalGuardStatus == 'demoted';
    final temporalGuardColor = temporalGuardStatus == 'blocked'
      ? const Color(0xFFFF5252)
      : const Color(0xFFFFB74D);

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1F3A),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
        boxShadow: [
          BoxShadow(
            color: isEnabled ? const Color(0xFF4CAF50).withOpacity(0.1) : Colors.black.withOpacity(0.2),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isCoolingDown) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFFFA726).withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFFFA726).withOpacity(0.35)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.timer_outlined, color: Color(0xFFFFA726), size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Cooling down until ${DateFormat('HH:mm').format(drawdownPauseUntil.toLocal())}',
                      style: GoogleFonts.poppins(
                        color: const Color(0xFFFFCC80),
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (idleReason.isNotEmpty && openPositionsCount == 0) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF00E5FF).withOpacity(0.10),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF00E5FF).withOpacity(0.28)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 1),
                    child: Icon(Icons.info_outline, color: Color(0xFF00E5FF), size: 16),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      idleReason,
                      style: GoogleFonts.poppins(
                        color: const Color(0xFFB3F5FF),
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (showTemporalGuard) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: temporalGuardColor.withOpacity(0.10),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: temporalGuardColor.withOpacity(0.35)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: Icon(
                      temporalGuardStatus == 'blocked' ? Icons.block_outlined : Icons.tune_outlined,
                      color: temporalGuardColor,
                      size: 16,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          temporalGuardHeadline.isNotEmpty ? temporalGuardHeadline : 'Adaptive time guard',
                          style: GoogleFonts.poppins(
                            color: temporalGuardColor,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (temporalGuardReason.isNotEmpty)
                          Text(
                            temporalGuardReason,
                            style: GoogleFonts.poppins(
                              color: Colors.white70,
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
          // Header row
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(botId, style: GoogleFonts.poppins(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Text(strategy, style: GoogleFonts.poppins(color: Colors.white70, fontSize: 12)),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: brokerAccent.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: brokerAccent.withOpacity(0.5),
                            ),
                          ),
                          child: Text(
                            brokerLabel,
                            style: GoogleFonts.poppins(
                              color: brokerAccent,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: isEnabled
                    ? const Color(0xFF4CAF50).withOpacity(0.2)
                    : Colors.grey.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isEnabled
                      ? const Color(0xFF4CAF50)
                      : Colors.grey,
                  ),
                ),
                child: Text(
                  status,
                  style: GoogleFonts.poppins(
                    color: isEnabled
                      ? const Color(0xFF4CAF50)
                      : Colors.grey,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              if (isNewBot) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFFFEB3B), Color(0xFFFFC107)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    'NEW',
                    style: GoogleFonts.poppins(
                      color: const Color(0xFF0A0E21),
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 2),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.white.withOpacity(0.1)),
            ),
            child: Text(symbolStr, style: GoogleFonts.poppins(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500)),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildMetaChip(accountModeLabel, isDemoBot ? const Color(0xFF4CAF50) : const Color(0xFFFF5252)),
              _buildMetaChip('Profile: $profileLabel', const Color(0xFF00E5FF)),
              if (presetName.isNotEmpty)
                _buildMetaChip('Preset: $presetName', const Color(0xFFFFA726)),
              if (tradeAmount > 0)
                _buildMetaChip(
                  'Fixed: ${_formatAmount(currencyProvider, tradeAmount, decimals: tradeAmount == tradeAmount.roundToDouble() ? 0 : 2, currencyCode: displayCurrency)}',
                  const Color(0xFFAB47BC),
                ),
              if (showTemporalGuard)
                _buildMetaChip(
                  temporalGuardHeadline.isNotEmpty ? temporalGuardHeadline : 'Adaptive guard',
                  temporalGuardColor,
                ),
              _buildAdaptationChip(bot),
              if (isMicroAccount)
                _buildMetaChip('⚡ Micro Mode', const Color(0xFFFFB300)),
              if (isDemoBot && promotionStatus != 'not_applicable')
                _buildPromotionChip(bot),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Text('Running for ', style: GoogleFonts.poppins(color: Colors.white60, fontSize: 12)),
              Text(runtime, style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13)),
              const Spacer(),
              Text('Open P/L ', style: GoogleFonts.poppins(color: Colors.white60, fontSize: 12)),
              Text(_formatAmount(currencyProvider, floatingProfit, currencyCode: displayCurrency), style: GoogleFonts.poppins(color: floatingProfit >= 0 ? const Color(0xFF4CAF50) : const Color(0xFFFF5252), fontWeight: FontWeight.bold, fontSize: 13)),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Today closed (Realized) ', style: GoogleFonts.poppins(color: Colors.white60, fontSize: 12)),
                  const SizedBox(width: 4),
                  Tooltip(
                    message: 'Profit from positions closed today only, excluding current open positions.',
                    child: Icon(Icons.info_outline, size: 12, color: Colors.white54),
                  ),
                ],
              ),
              const SizedBox(width: 4),
              Text(_formatAmount(currencyProvider, todayClosedProfit, currencyCode: displayCurrency), style: GoogleFonts.poppins(color: todayClosedProfit >= 0 ? const Color(0xFF4CAF50) : const Color(0xFFFF5252), fontWeight: FontWeight.w600, fontSize: 12)),
              const Spacer(),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Session P/L (Today + Open) ', style: GoogleFonts.poppins(color: Colors.white60, fontSize: 12)),
                  const SizedBox(width: 4),
                  Tooltip(
                    message: 'Realized profit for today plus current open position profit.',
                    child: Icon(Icons.info_outline, size: 12, color: Colors.white54),
                  ),
                ],
              ),

              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    currentProfit >= 0 ? Icons.arrow_upward : Icons.arrow_downward,
                    color: currentProfit >= 0 ? const Color(0xFF4CAF50) : const Color(0xFFFF5252),
                    size: 14,
                  ),
                  Text(_formatAmount(currencyProvider, currentProfit, currencyCode: displayCurrency), style: GoogleFonts.poppins(color: currentProfit >= 0 ? const Color(0xFF4CAF50) : const Color(0xFFFF5252), fontWeight: FontWeight.w700, fontSize: 12)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _botStat('Trades', '$visibleTradeCount', const Color(0xFF00E5FF)),
              _botStat('Win Rate', '${winRate.toStringAsFixed(1)}%', const Color(0xFF4CAF50)),
              _botStat('All-time', _formatAmount(currencyProvider, allTimeProfit, currencyCode: displayCurrency), allTimeProfit >= 0 ? const Color(0xFF4CAF50) : const Color(0xFFFF5252)),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _botStat('ROI', '${roi.toStringAsFixed(1)}%', const Color(0xFFFFA726)),
              _botStat('Avg/Trade', _formatAmount(currencyProvider, avgTrade, decimals: 0, currencyCode: displayCurrency), const Color(0xFFAB47BC)),
              _botStat('Max Drawdown', _formatAmount(currencyProvider, maxDrawdown, decimals: 0, currencyCode: displayCurrency), const Color(0xFFFF5252)),
            ],
          ),
          // Account Balance & Equity
          if (accountBalance > 0) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF00E5FF).withOpacity(0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF00E5FF).withOpacity(0.2)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.account_balance_wallet, color: Color(0xFF00E5FF), size: 16),
                          const SizedBox(width: 8),
                          Text('Balance', style: GoogleFonts.poppins(color: Colors.white60, fontSize: 12)),
                        ],
                      ),
                      Flexible(
                        child: Text(
                          _formatAmount(currencyProvider, accountBalance, currencyCode: displayCurrency),
                          style: GoogleFonts.poppins(color: const Color(0xFF00E5FF), fontWeight: FontWeight.w700, fontSize: 14),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  if (configuredCapital > 0) ...[
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.savings_outlined, color: Color(0xFFFFA726), size: 16),
                            const SizedBox(width: 8),
                            Text('Trade Capital', style: GoogleFonts.poppins(color: Colors.white60, fontSize: 12)),
                          ],
                        ),
                        Flexible(
                          child: Text(
                            _formatAmount(currencyProvider, configuredCapital, currencyCode: displayCurrency),
                            style: GoogleFonts.poppins(color: const Color(0xFFFFA726), fontWeight: FontWeight.w600, fontSize: 13),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (investedCapital > 0 && (configuredCapital <= 0 || (investedCapital - configuredCapital).abs() >= 0.01)) ...[
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.insights_outlined, color: Color(0xFFAB47BC), size: 16),
                            const SizedBox(width: 8),
                            Text('Invested', style: GoogleFonts.poppins(color: Colors.white60, fontSize: 12)),
                          ],
                        ),
                        Flexible(
                          child: Text(
                            _formatAmount(currencyProvider, investedCapital, currencyCode: displayCurrency),
                            style: GoogleFonts.poppins(color: const Color(0xFFAB47BC), fontWeight: FontWeight.w600, fontSize: 13),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (accountEquity > 0) ...[
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.trending_up, color: Color(0xFF4CAF50), size: 16),
                            const SizedBox(width: 8),
                            Text('Equity', style: GoogleFonts.poppins(color: Colors.white60, fontSize: 12)),
                          ],
                        ),
                        Flexible(
                          child: Text(
                            _formatAmount(currencyProvider, accountEquity, currencyCode: displayCurrency),
                            style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
          // Open Positions
          if (openPositionsCount > 0) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(Icons.candlestick_chart, color: Color(0xFFFFA726), size: 16),
                const SizedBox(width: 6),
                Text(
                  'Open Positions ($openPositionsCount)',
                  style: GoogleFonts.poppins(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 6),
            ...openPositions.take(5).map((pos) {
              final posTicket = (pos['ticket'] ?? pos['position'] ?? pos['positionId'])?.toString() ?? '';
              final posSymbol = pos['symbol']?.toString() ?? '';
              final posType = pos['type']?.toString() ?? '';
              final posVolume = double.tryParse(pos['volume']?.toString() ?? '0') ?? 0;
              final posEntry = double.tryParse(pos['entryPrice']?.toString() ?? '0') ?? 0;
              final posCurrent = double.tryParse(pos['currentPrice']?.toString() ?? '0') ?? 0;
              final posProfit = double.tryParse(pos['profit']?.toString() ?? '0') ?? 0;
              final isBuy = posType.toUpperCase().contains('BUY');
              final hasProtectionData =
                  (pos['profitProtectionArmed'] == true) ||
                  (pos['lockedProfitFloor'] != null) ||
                  (pos['breakEvenFloor'] != null);
              return Container(
                margin: const EdgeInsets.only(bottom: 4),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.04),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white.withOpacity(0.06)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          isBuy ? Icons.arrow_upward : Icons.arrow_downward,
                          color: isBuy ? const Color(0xFF4CAF50) : const Color(0xFFFF5252),
                          size: 14,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          posSymbol,
                          style: GoogleFonts.poppins(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: (isBuy ? const Color(0xFF4CAF50) : const Color(0xFFFF5252)).withOpacity(0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            isBuy ? 'BUY' : 'SELL',
                            style: GoogleFonts.poppins(
                              color: isBuy ? const Color(0xFF4CAF50) : const Color(0xFFFF5252),
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const Spacer(),
                        Flexible(
                          child: Text(
                            _formatPositionSize(posVolume, isBinance: isBinanceBot),
                            style: GoogleFonts.poppins(color: Colors.white54, fontSize: 11),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            '@ ${posEntry.toStringAsFixed(posEntry > 100 ? 2 : 5)}',
                            style: GoogleFonts.poppins(color: Colors.white70, fontSize: 11),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (posCurrent > 0 || posProfit != 0) ...[
                          const SizedBox(width: 6),
                          Text(
                            'P/L ${_formatAmount(currencyProvider, posProfit, currencyCode: displayCurrency)}',
                            style: GoogleFonts.poppins(
                              color: posProfit >= 0 ? const Color(0xFF4CAF50) : const Color(0xFFFF5252),
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                        if (posTicket.isNotEmpty) ...[
                          const SizedBox(width: 6),
                          InkWell(
                            borderRadius: BorderRadius.circular(6),
                            onTap: () async {
                              final shouldClose = await showDialog<bool>(
                                context: context,
                                builder: (dialogContext) => AlertDialog(
                                  backgroundColor: const Color(0xFF0A0E21),
                                  title: Text(
                                    'Close Position?',
                                    style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w700),
                                  ),
                                  content: Text(
                                    '$posSymbol (${isBuy ? 'BUY' : 'SELL'}) ticket $posTicket will be closed now.',
                                    style: GoogleFonts.poppins(color: Colors.white70),
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(dialogContext, false),
                                      child: Text('Cancel', style: GoogleFonts.poppins(color: Colors.white70)),
                                    ),
                                    TextButton(
                                      onPressed: () => Navigator.pop(dialogContext, true),
                                      child: Text('Close', style: GoogleFonts.poppins(color: Colors.redAccent)),
                                    ),
                                  ],
                                ),
                              );

                              if (shouldClose != true) return;
                              final botService = context.read<BotService>();
                              final closed = await botService.closeBotPosition(botId.toString(), posTicket);
                              if (!mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(closed ? 'Position closed' : (botService.errorMessage ?? 'Failed to close position')),
                                  backgroundColor: closed ? Colors.green : Colors.red,
                                  duration: const Duration(seconds: 2),
                                ),
                              );
                              if (closed) {
                                setState(() {});
                              }
                            },
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: Colors.redAccent.withOpacity(0.18),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: Colors.redAccent.withOpacity(0.45)),
                              ),
                              child: const Icon(Icons.close, color: Colors.redAccent, size: 14),
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (hasProtectionData) ...[
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          if (pos['profitProtectionBucket'] != null)
                            _buildProtectionChip(
                              'Protect ${pos['profitProtectionBucket']}',
                              const Color(0xFF26A69A),
                            ),
                          if ((double.tryParse(pos['lockedProfitFloor']?.toString() ?? '0') ?? 0) > 0)
                            _buildProtectionChip(
                              'Floor ${_formatAmount(currencyProvider, double.tryParse(pos['lockedProfitFloor']?.toString() ?? '0') ?? 0, currencyCode: displayCurrency)}',
                              const Color(0xFF26A69A),
                            ),
                          if ((double.tryParse(pos['breakEvenFloor']?.toString() ?? '0') ?? 0) > 0)
                            _buildProtectionChip(
                              'BE+ ${_formatAmount(currencyProvider, double.tryParse(pos['breakEvenFloor']?.toString() ?? '0') ?? 0, currencyCode: displayCurrency)}',
                              const Color(0xFF42A5F5),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              );
            }),
            if (openPositionsCount > 5)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '+${openPositionsCount - 5} more positions',
                  style: GoogleFonts.poppins(color: Colors.white38, fontSize: 11),
                ),
              ),
            if (activeSymbolCooldowns.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: activeSymbolCooldowns.take(3).map((cooldown) {
                  final cooldownUntil = DateTime.tryParse(cooldown['until']?.toString() ?? '');
                  final label = cooldownUntil == null
                      ? '${cooldown['symbol']} cooldown'
                      : '${cooldown['symbol']} until ${DateFormat('HH:mm').format(cooldownUntil.toLocal())}';
                  return _buildProtectionChip(label, const Color(0xFFFFA726));
                }).toList(),
              ),
            ],
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: isEnabled 
                        ? [const Color(0xFFFFA726), const Color(0xFFFF7043)]
                        : [const Color(0xFF66BB6A), const Color(0xFF43A047)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: (isEnabled ? const Color(0xFFFFA726) : const Color(0xFF66BB6A)).withOpacity(0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () async {
                        final botService = context.read<BotService>();
                        final result = isEnabled
                          ? await botService.stopBotTrading(botId)
                          : await botService.startBotTrading(botId);
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Text(result ? (isEnabled ? 'Bot stopped' : 'Bot started') : 'Action failed'),
                          backgroundColor: result ? Colors.green : Colors.red,
                          duration: const Duration(seconds: 2),
                        ));
                        setState(() {});
                      },
                      borderRadius: BorderRadius.circular(12),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(isEnabled ? Icons.pause_circle : Icons.play_circle, size: 18),
                            const SizedBox(width: 8),
                            Text(
                              isEnabled ? 'Stop' : 'Start',
                              style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF00E5FF), Color(0xFF00BCD4)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF00E5FF).withOpacity(0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () {
                        Navigator.push(context, MaterialPageRoute(
                          builder: (_) => BotAnalyticsScreen(bot: bot),
                        ));
                      },
                      borderRadius: BorderRadius.circular(12),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.analytics, size: 18),
                            const SizedBox(width: 8),
                            Text(
                              'Analytics',
                              style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              // Overflow menu for less-used actions (Delete)
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert, color: Colors.white54, size: 22),
                color: const Color(0xFF1A1F3A),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                onSelected: (value) async {
                  if (value == 'edit') {
                    final isEnabled = bot['enabled'] == true;
                    if (isEnabled) {
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Stop the bot before reconfiguring it.'),
                          backgroundColor: Colors.orange,
                          duration: Duration(seconds: 3),
                        ),
                      );
                      return;
                    }
                    final updated = await Navigator.push<bool>(
                      context,
                      MaterialPageRoute(
                        builder: (_) => BotConfigurationRoute(botId: botId),
                      ),
                    );
                    if (updated == true && mounted) {
                      await _loadTradingMode();
                    }
                  } else if (value == 'clone') {
                    final cloned = await Navigator.push<bool>(
                      context,
                      MaterialPageRoute(
                        builder: (_) => BotConfigurationRoute(
                          cloneFromBotId: botId,
                        ),
                      ),
                    );
                    if (cloned == true && mounted) {
                      await _loadTradingMode();
                    }
                  } else if (value == 'promote') {
                    if (!isPromotionEligible) {
                      final promotionMessage = promotionStatus == 'expired'
                          ? 'This demo bot did not qualify for live promotion within the evaluation window.'
                          : 'Promotion to live requires a demo bot that passes the live test window with profit and at least 3 completed trades.';
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(promotionMessage),
                          backgroundColor: Colors.orange,
                          duration: Duration(seconds: 3),
                        ),
                      );
                      return;
                    }
                    final promoted = await Navigator.push<bool>(
                      context,
                      MaterialPageRoute(
                        builder: (_) => BotConfigurationRoute(
                          cloneFromBotId: botId,
                          promoteToLive: true,
                        ),
                      ),
                    );
                    if (promoted == true && mounted) {
                      await _loadTradingMode();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Live bot created from demo settings.'),
                          backgroundColor: Color(0xFF00C853),
                          duration: Duration(seconds: 3),
                        ),
                      );
                    }
                   } else if (value == 'export_pdf') {
                     _exportBotReportPdf(context, bot);
                   } else if (value == 'share_report') {
                     _shareBotReport(context, bot);
                   } else if (value == 'delete') {
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: Text('Delete $botId?', style: const TextStyle(color: Colors.white)),
                        backgroundColor: const Color(0xFF0A0E21),
                        content: const Text(
                          'This action cannot be undone.',
                          style: TextStyle(color: Colors.white70),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: Text('Cancel', style: GoogleFonts.poppins(color: Colors.white70)),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, true),
                            child: Text('Delete', style: GoogleFonts.poppins(color: Colors.red)),
                          ),
                        ],
                      ),
                    );
                    if (confirmed != true) return;
                    final botService = context.read<BotService>();
                    final deleted = await botService.deleteBot(botId);
                    if (!mounted) return;
                    if (deleted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('$botId deleted'),
                          backgroundColor: Colors.red,
                          duration: const Duration(seconds: 2),
                        ),
                      );
                      setState(() {});
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(botService.errorMessage ?? 'Failed to delete $botId'),
                          backgroundColor: Colors.orange,
                          duration: const Duration(seconds: 3),
                        ),
                      );
                    }
                  }
                },
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: 'edit',
                    child: Row(
                      children: [
                        const Icon(Icons.edit_outlined, color: Color(0xFF00E5FF), size: 18),
                        const SizedBox(width: 8),
                        Text('Reconfigure Bot', style: GoogleFonts.poppins(color: const Color(0xFF00E5FF), fontSize: 13)),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'clone',
                    child: Row(
                      children: [
                        const Icon(Icons.copy_all_outlined, color: Color(0xFF4CAF50), size: 18),
                        const SizedBox(width: 8),
                        Text('Clone Bot', style: GoogleFonts.poppins(color: const Color(0xFF4CAF50), fontSize: 13)),
                      ],
                    ),
                  ),
                  if (isDemoBot)
                    PopupMenuItem(
                      value: 'promote',
                      enabled: isPromotionEligible,
                      child: Row(
                        children: [
                          Icon(
                            Icons.trending_up_outlined,
                            color: isPromotionEligible ? const Color(0xFFFFB74D) : Colors.white38,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            isPromotionEligible
                                ? 'Promote To Live'
                                : promotionStatus == 'expired'
                                    ? 'Promotion Expired'
                                    : 'Promote To Live (evaluating)',
                            style: GoogleFonts.poppins(
                              color: isPromotionEligible ? const Color(0xFFFFB74D) : Colors.white38,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  PopupMenuItem(
                    value: 'export_pdf',
                    child: Row(
                      children: [
                        const Icon(Icons.picture_as_pdf_outlined, color: Color(0xFF4CAF50), size: 18),
                        const SizedBox(width: 8),
                        Text('Export PDF Report', style: GoogleFonts.poppins(color: const Color(0xFF4CAF50), fontSize: 13)),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'share_report',
                    child: Row(
                      children: [
                        const Icon(Icons.share_outlined, color: Color(0xFF00E5FF), size: 18),
                        const SizedBox(width: 8),
                        Text('Share Report', style: GoogleFonts.poppins(color: const Color(0xFF00E5FF), fontSize: 13)),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        const Icon(Icons.delete_outline, color: Colors.redAccent, size: 18),
                        const SizedBox(width: 8),
                        Text('Delete Bot', style: GoogleFonts.poppins(color: Colors.redAccent, fontSize: 13)),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
     );
   }

  Future<void> _exportBotReportPdf(BuildContext context, Map<String, dynamic> bot) async {
    try {
      final tradeHistory = List<Map<String, dynamic>>.from(bot['tradeHistory'] ?? []);
      final openPositions = List<Map<String, dynamic>>.from(bot['openPositions'] ?? bot['openPositionsPreview'] ?? []);
      final pdf = await FinancialExportService.generateBotReportPdf(
        bot: bot,
        tradeHistory: tradeHistory,
        openPositions: openPositions,
      );
      final filename = 'zwesta_bot_report_${bot['botId'] ?? DateTime.now().millisecondsSinceEpoch}_${DateTime.now().millisecondsSinceEpoch}.pdf';
      final path = await FinancialExportService.savePdfToDownloads(filename, pdf);
      if (!context.mounted) return;
      if (path != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('PDF saved to $path'), backgroundColor: Colors.green),
        );
      } else {
        final fallbackPath = await FinancialExportService.savePdf(filename, pdf);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('PDF saved to $fallbackPath'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('PDF export failed: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _shareBotReport(BuildContext context, Map<String, dynamic> bot) async {
    try {
      final tradeHistory = List<Map<String, dynamic>>.from(bot['tradeHistory'] ?? []);
      final openPositions = List<Map<String, dynamic>>.from(bot['openPositions'] ?? bot['openPositionsPreview'] ?? []);
      final pdf = await FinancialExportService.generateBotReportPdf(
        bot: bot,
        tradeHistory: tradeHistory,
        openPositions: openPositions,
      );
      final filename = 'zwesta_bot_report_${bot['botId'] ?? DateTime.now().millisecondsSinceEpoch}.pdf';
      await FinancialExportService.sharePdf(pdf, filename);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Share failed: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Widget _buildProtectionChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Text(
        label,
        style: GoogleFonts.poppins(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _botStat(String label, String value, Color color) => Expanded(
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: color.withOpacity(0.3)),
            ),
            child: Text(
              value,
              style: GoogleFonts.poppins(color: color, fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(height: 4),
          Text(label, style: GoogleFonts.poppins(color: Colors.white60, fontSize: 10)),
        ],
      ),
    );

  // IG Markets integration removed

  /// Quick broker button for dashboard quick actions
  Widget _quickBrokerButton({
    required String label,
    required Color color,
    required VoidCallback onTap,
    dynamic icon,
    String? description,
  }) => GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: color.withOpacity(0.15),
          border: Border.all(color: color.withOpacity(0.5)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon is String)
              Text(
                icon,
                style: const TextStyle(fontSize: 24),
              )
            else if (icon is IconData)
              Icon(icon, color: color, size: 20),
            const SizedBox(height: 4),
            Text(
              label,
              style: GoogleFonts.poppins(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (description != null) ...[
              const SizedBox(height: 2),
              Text(
                description,
                style: GoogleFonts.poppins(
                  color: color.withOpacity(0.7),
                  fontSize: 9,
                ),
              ),
            ],
          ],
        ),
      ),
    );

  /// Create bot for specific broker - with quick create option for Binance and Exness
  void _createBotForBroker(BuildContext context, String brokerName) async {
    if (brokerName == 'Binance') {
      _showBinanceQuickCreateDialog(context);
    } else if (brokerName == 'Exness') {
      _showExnessQuickCreateDialog(context);
    } else {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => const BotConfigurationRoute(),
        ),
      );
    }
  }

  /// Show quick create dialog for Binance with preset options
  void _showBinanceQuickCreateDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        title: Row(
          children: [
            const Text('₿ ', style: TextStyle(fontSize: 24, color: Color(0xFFF3BA2F))),
            Text('Quick Binance Bot', style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w700)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Choose a trading preset to create your bot instantly:',
              style: GoogleFonts.poppins(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 20),
            _binancePresetOption(
              dialogContext,
              '🚀 Top Edge (6 pairs)',
              'Best win rates: BTC, ETH, SOL, XRP, BNB, LTC',
              'top_edge',
              Icons.trending_up,
            ),
            const SizedBox(height: 10),
            _binancePresetOption(
              dialogContext,
              '💎 Micro Account (< \$20)',
              'Auto-selected cheap pairs: XRP, ADA, DOGE, TRX, XLM',
              'micro_account',
              Icons.account_balance_wallet,
            ),
            const SizedBox(height: 10),
            _binancePresetOption(
              dialogContext,
              '⚖️  Balanced (6 pairs)',
              'Low-medium risk: BTC, ETH, LINK, ADA, DOGE, MATIC',
              'balanced',
              Icons.balance,
            ),
            const SizedBox(height: 10),
            _binancePresetOption(
              dialogContext,
              '🔶 DeFi & L2 (6 pairs)',
              'High volatility: UNI, AAVE, APT, INJ, SUI, FTM',
              'defi',
              Icons.hexagon,
            ),
            const SizedBox(height: 10),
            _binancePresetOption(
              dialogContext,
              '📈 Large Cap (6 pairs)',
              'Stable focus: BTC, ETH, BNB, SOL, ADA, XRP',
              'large_cap_only',
              Icons.bar_chart,
            ),
            const SizedBox(height: 20),
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                // Show standard configuration screen
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const BotConfigurationRoute()),
                );
              },
              child: Text(
                'Custom Setup',
                style: GoogleFonts.poppins(color: const Color(0xFF00E5FF), fontSize: 13),
              ),
            ),
          ],
        ),
),
      );
  }

  /// Show quick create dialog for Exness with preset options
  void _showExnessQuickCreateDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        title: Row(
          children: [
            const Text('🦁 ', style: TextStyle(fontSize: 24, color: Color(0xFF00E5FF))),
            Text('Quick Exness Bot', style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w700)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Choose a trading preset to create your bot instantly:',
              style: GoogleFonts.poppins(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 20),
            _exnessPresetOption(
              dialogContext,
              '🚀 Edge Pairs (5 pairs)',
              'Best win rates: EURUSD, GBPUSD, USDJPY, XAUUSD, US500',
              'edge_pairs',
              Icons.trending_up,
            ),
            const SizedBox(height: 10),
            _exnessPresetOption(
              dialogContext,
              '💱 Majors (5 pairs)',
              'Low-medium risk: EURUSD, GBPUSD, USDJPY, USDCHF, AUDUSD',
              'majors',
              Icons.bar_chart,
            ),
            const SizedBox(height: 10),
            _exnessPresetOption(
              dialogContext,
              '🥇 Gold (1 pair)',
              'Safe haven: XAUUSD only',
              'gold',
              Icons.attach_money,
            ),
            const SizedBox(height: 10),
            _exnessPresetOption(
              dialogContext,
              '📊 Indices (2 pairs)',
              'High volatility: US500, US30',
              'indices',
              Icons.show_chart,
            ),
            const SizedBox(height: 20),
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const BotConfigurationRoute()),
                );
              },
              child: Text(
                'Custom Setup',
                style: GoogleFonts.poppins(color: const Color(0xFF00E5FF), fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Individual Exness preset option button
  Widget _exnessPresetOption(BuildContext context, String title, String description, String preset, IconData icon) => InkWell(
      onTap: () => _quickCreateExnessBot(context, preset),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFF00E5FF).withOpacity(0.3)),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: const Color(0xFF00E5FF).withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF00E5FF).withOpacity(0.4)),
              ),
              child: Icon(icon, color: const Color(0xFF00E5FF), size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: GoogleFonts.poppins(color: const Color(0xFF00E5FF), fontWeight: FontWeight.w600, fontSize: 12)),
                  const SizedBox(height: 4),
                  Text(description, style: GoogleFonts.poppins(color: Colors.white60, fontSize: 11)),
                ],
              ),
            ),
          ],
        ),
      ),
    );

  /// Quick create Exness bot with preset
  void _quickCreateExnessBot(BuildContext context, String preset) async {
    Navigator.pop(context); // Close dialog

    try {
      final prefs = await SharedPreferences.getInstance();
      final sessionToken = prefs.getString('auth_token');

      if (sessionToken == null || sessionToken.isEmpty) {
        _showErrorSnackbar('⚠️ Session expired. Please login again.');
        return;
      }

      final brokerService = Provider.of<BrokerCredentialsService>(context, listen: false);
      final credential = brokerService.activeCredential;

      if (credential == null) {
        _showErrorSnackbar('⚠️ Please setup Exness broker integration first');
        return;
      }

      if (credential.broker.toLowerCase() != 'exness') {
        _showErrorSnackbar('⚠️ This quick create only works with Exness broker');
        return;
      }

      if (credential.credentialId.isEmpty) {
        _showErrorSnackbar('⚠️ Invalid Exness credential');
        return;
      }

      // Show loading dialog
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A2E),
          content: Row(
            children: [
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(Colors.white60)),
              ),
              const SizedBox(width: 16),
              Text('Creating quick bot...', style: GoogleFonts.poppins(color: Colors.white70)),
            ],
          ),
        ),
      );

      final response = await http.post(
        Uri.parse('${EnvironmentConfig.apiUrl}/api/bot/quick-create-exness'),
        headers: {
          'Content-Type': 'application/json',
          'X-Session-Token': sessionToken,
        },
        body: jsonEncode({
          'credentialId': credential.credentialId,
          'preset': preset,
        }),
      ).timeout(const Duration(seconds: 15));

      if (!mounted) return;
      Navigator.pop(context); // Close loading dialog

      if (response.statusCode == 201 || response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final botId = data['botId'] ?? 'Bot';
        final pairs = (data['pairs'] as List?)?.join(', ') ?? 'N/A';

        bool botStarted = false;
        try {
          final startResponse = await http.post(
            Uri.parse('${EnvironmentConfig.apiUrl}/api/bot/start'),
            headers: {
              'Content-Type': 'application/json',
              'X-Session-Token': sessionToken,
            },
            body: jsonEncode({'botId': botId}),
          ).timeout(const Duration(seconds: 15));

          botStarted = startResponse.statusCode == 200;
          debugPrint('Bot start response: ${startResponse.statusCode}');
        } catch (startError) {
          debugPrint('Bot start failed after quick-create: $startError');
        }

        final botService = Provider.of<BotService>(context, listen: false);
        await botService.fetchActiveBots(tradingMode: _tradingMode, force: true);

        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: const Color(0xFF1A1A2E),
            title: Row(
              children: [
                const Text('✅', style: TextStyle(fontSize: 24)),
                const SizedBox(width: 8),
                Expanded(child: Text('Bot Created', style: GoogleFonts.poppins(color: const Color(0xFF4CAF50), fontWeight: FontWeight.w700))),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Your quick bot is ready!', style: GoogleFonts.poppins(color: Colors.white70, fontSize: 13)),
                const SizedBox(height: 12),
                _infoRow('Bot ID', botId, Colors.white60),
                const SizedBox(height: 8),
                _infoRow('Pairs', pairs, Colors.white60),
                const SizedBox(height: 8),
                _infoRow('Status', botStarted ? '🟢 Running' : '✅ Created', botStarted ? const Color(0xFF4CAF50) : const Color(0xFFF3BA2F)),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () async {
                  Navigator.pop(ctx);
                  final botService = Provider.of<BotService>(context, listen: false);
                  await botService.fetchActiveBots(tradingMode: _tradingMode, force: true);
                  if (mounted) {
                    setState(() {});
                  }
                },
                child: Text('Done', style: GoogleFonts.poppins(color: const Color(0xFF00E5FF))),
              ),
            ],
          ),
        );
      } else {
        final error = jsonDecode(response.body)['error'] ?? 'Failed to create bot';
        _showErrorSnackbar('❌ $error');
      }
    } catch (e) {
      _showErrorSnackbar('❌ Error: $e');
    }
  }

  /// Individual Binance preset option button
  Widget _binancePresetOption(BuildContext context, String title, String description, String preset, IconData icon) => InkWell(
      onTap: () => _quickCreateBinanceBot(context, preset),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFF3BA2F).withOpacity(0.3)),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: const Color(0xFFF3BA2F).withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFF3BA2F).withOpacity(0.4)),
              ),
              child: Icon(icon, color: const Color(0xFFF3BA2F), size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 12)),
                  const SizedBox(height: 4),
                  Text(description, style: GoogleFonts.poppins(color: Colors.white60, fontSize: 11)),
                ],
              ),
            ),
          ],
        ),
      ),
    );

/// Quick create Binance bot with preset
  void _quickCreateBinanceBot(BuildContext context, String preset) async {
    Navigator.pop(context); // Close dialog
    
    try {
      final prefs = await SharedPreferences.getInstance();
      final sessionToken = prefs.getString('auth_token');
      
      if (sessionToken == null || sessionToken.isEmpty) {
        _showErrorSnackbar('⚠️ Session expired. Please login again.');
        return;
      }
      
      // Use the existing broker service from provider instead of creating a new one
      final brokerService = Provider.of<BrokerCredentialsService>(context, listen: false);
      final credential = brokerService.activeCredential;
      
      if (credential == null) {
        _showErrorSnackbar('⚠️ Please setup Binance broker integration first');
        return;
      }
      
      if (credential.broker.toLowerCase() != 'binance') {
        _showErrorSnackbar('⚠️ This quick create only works with Binance broker');
        return;
      }
      
      // Verify credentialId exists
      if (credential.credentialId.isEmpty) {
        _showErrorSnackbar('⚠️ Invalid Binance credential');
        return;
      }
      
      // Show loading dialog
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A2E),
          content: Row(
            children: [
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(Colors.white60)),
              ),
              const SizedBox(width: 16),
              Text('Creating quick bot...', style: GoogleFonts.poppins(color: Colors.white70)),
            ],
          ),
        ),
      );
      
      // Call quick create endpoint
      final response = await http.post(
        Uri.parse('${EnvironmentConfig.apiUrl}/api/bot/quick-create'),
        headers: {
          'Content-Type': 'application/json',
          'X-Session-Token': sessionToken,
        },
        body: jsonEncode({
          'credentialId': credential.credentialId,
          'preset': preset,
        }),
      ).timeout(const Duration(seconds: 15));
      
if (!mounted) return;
      Navigator.pop(context); // Close loading dialog
      
      if (response.statusCode == 201 || response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final botId = data['botId'] ?? 'Bot';
        final pairs = (data['pairs'] as List?)?.join(', ') ?? 'N/A';
        
        // Immediate bot list refresh before showing success dialog
        final botService = Provider.of<BotService>(context, listen: false);
        await botService.fetchActiveBots(tradingMode: _tradingMode, force: true);
        
        // Show success dialog
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: const Color(0xFF1A1A2E),
            title: Row(
              children: [
                const Text('✅', style: TextStyle(fontSize: 24)),
                const SizedBox(width: 8),
                Expanded(child: Text('Bot Created', style: GoogleFonts.poppins(color: const Color(0xFF4CAF50), fontWeight: FontWeight.w700))),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Your quick bot is ready!', style: GoogleFonts.poppins(color: Colors.white70, fontSize: 13)),
                const SizedBox(height: 12),
                _infoRow('Bot ID', botId, Colors.white60),
                const SizedBox(height: 8),
                _infoRow('Pairs', pairs, Colors.white60),
                const SizedBox(height: 8),
                _infoRow('Status', '🟢 Running', const Color(0xFF4CAF50)),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () async {
                  Navigator.pop(ctx);
                  // Refresh bot list and await completion
                  final botService = Provider.of<BotService>(context, listen: false);
                  await botService.fetchActiveBots(tradingMode: _tradingMode, force: true);
                  if (mounted) {
                    setState(() {});
                  }
                },
                child: Text('Done', style: GoogleFonts.poppins(color: const Color(0xFF00E5FF))),
              ),
            ],
          ),
        );
      } else {
        final error = jsonDecode(response.body)['error'] ?? 'Failed to create bot';
        _showErrorSnackbar('❌ $error');
      }
    } catch (e) {
      _showErrorSnackbar('❌ Error: $e');
    }
  }

  /// Helper widget to display info rows
  Widget _infoRow(String label, String value, Color valueColor) => Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: GoogleFonts.poppins(color: Colors.white60, fontSize: 12)),
        Text(value, style: GoogleFonts.poppins(color: valueColor, fontSize: 12, fontWeight: FontWeight.w600)),
      ],
    );

  /// Show error snackbar
  void _showErrorSnackbar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: GoogleFonts.poppins(color: Colors.white)),
        backgroundColor: Colors.red.shade700,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Widget _filterChip(String label, String value) {
    final isSelected = _filterStatus == value;
    return GestureDetector(
      onTap: () => setState(() => _filterStatus = value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF00E5FF).withOpacity(0.2) : Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: isSelected ? const Color(0xFF00E5FF) : Colors.white12),
        ),
        child: Text(
          label,
          style: GoogleFonts.poppins(
            color: isSelected ? const Color(0xFF00E5FF) : Colors.white38,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _buildNewestBotCard(Map<String, dynamic> bot, CurrencyProvider currencyProvider) => _buildUnifiedBotCard(bot, currencyProvider);

  Widget _buildStatCard(String value, String label, Color color) => Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            value,
            style: GoogleFonts.poppins(
              color: color,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: GoogleFonts.poppins(
              color: Colors.white60,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );

  Widget _buildMiniBot(Map<String, dynamic> bot) {
    final botId = bot['botId'] ?? 'Unknown';
    final isEnabled = bot['enabled'] == true;
    final profit = double.tryParse(bot['profit']?.toString() ?? '0') ?? 0;
    final displayCurrency = _botDisplayCurrency(bot);

    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => BotAnalyticsScreen(bot: bot))),
      child: Container(
        width: 140,
        margin: const EdgeInsets.only(right: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: isEnabled
                ? [const Color(0xFF4CAF50).withOpacity(0.1), const Color(0xFF00E5FF).withOpacity(0.1)]
                : [Colors.grey.withOpacity(0.1), Colors.grey.withOpacity(0.05)],
          ),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: isEnabled ? const Color(0xFF4CAF50).withOpacity(0.3) : Colors.white12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Icon(Icons.smart_toy, color: isEnabled ? const Color(0xFF4CAF50) : Colors.grey, size: 16),
                const SizedBox(width: 6),
                Expanded(child: Text(botId, style: GoogleFonts.poppins(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis)),
              ],
            ),
            Text(
              '${_symbolForCode(displayCurrency)}${profit.toStringAsFixed(2)}',
              style: GoogleFonts.poppins(
                color: profit >= 0 ? const Color(0xFF4CAF50) : const Color(0xFFFF5252),
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: isEnabled ? const Color(0xFF4CAF50).withOpacity(0.15) : Colors.grey.withOpacity(0.15),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                isEnabled ? 'Active' : 'Inactive',
                style: GoogleFonts.poppins(color: isEnabled ? const Color(0xFF4CAF50) : Colors.grey, fontSize: 9, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

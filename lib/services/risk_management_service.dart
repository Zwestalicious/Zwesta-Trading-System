import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/trading_signal.dart';
import '../models/trade.dart';
import '../models/account.dart';
import '../utils/environment_config.dart';

/// A single profit-tier scaling multiplier, used when the bot's realized
/// P&L exceeds the given percentage of account balance.
class _ProfitScaleTier {
  final double minPctOfBalance;
  final double tradeAmountMult;
  final double atrMult;

  const _ProfitScaleTier({
    required this.minPctOfBalance,
    required this.tradeAmountMult,
    required this.atrMult,
  });
}

/// Risk validation result returned by the RiskManagementService.
class RiskValidationResult {
  final bool approved;
  final double? adjustedPositionSize;
  final String? rejectionReason;
  final RiskCheckFlags flags;

  const RiskValidationResult({
    required this.approved,
    this.adjustedPositionSize,
    this.rejectionReason,
    this.flags = const RiskCheckFlags(),
  });

  @override
  String toString() =>
      'RiskValidationResult(approved: $approved, adjustedPositionSize: $adjustedPositionSize, reason: $rejectionReason, flags: $flags)';
}

/// Bitmask-style record of which risk checks were triggered.
class RiskCheckFlags {
  final bool maxContractsPerSymbol;
  final bool dailyLossLimit;
  final bool maxOpenPositions;
  final bool exposureLimit;
  final bool accountEquityThreshold;

  const RiskCheckFlags({
    this.maxContractsPerSymbol = false,
    this.dailyLossLimit = false,
    this.maxOpenPositions = false,
    this.exposureLimit = false,
    this.accountEquityThreshold = false,
  });

  RiskCheckFlags copyWith({
    bool? maxContractsPerSymbol,
    bool? dailyLossLimit,
    bool? maxOpenPositions,
    bool? exposureLimit,
    bool? accountEquityThreshold,
  }) {
    return RiskCheckFlags(
      maxContractsPerSymbol: maxContractsPerSymbol ?? this.maxContractsPerSymbol,
      dailyLossLimit: dailyLossLimit ?? this.dailyLossLimit,
      maxOpenPositions: maxOpenPositions ?? this.maxOpenPositions,
      exposureLimit: exposureLimit ?? this.exposureLimit,
      accountEquityThreshold: accountEquityThreshold ?? this.accountEquityThreshold,
    );
  }

  bool get anyTriggered =>
      maxContractsPerSymbol ||
      dailyLossLimit ||
      maxOpenPositions ||
      exposureLimit ||
      accountEquityThreshold;

  Map<String, dynamic> toJson() => {
        'maxContractsPerSymbol': maxContractsPerSymbol,
        'dailyLossLimit': dailyLossLimit,
        'maxOpenPositions': maxOpenPositions,
        'exposureLimit': exposureLimit,
        'accountEquityThreshold': accountEquityThreshold,
      };

  factory RiskCheckFlags.fromJson(Map<String, dynamic> json) => RiskCheckFlags(
        maxContractsPerSymbol: json['maxContractsPerSymbol'] == true,
        dailyLossLimit: json['dailyLossLimit'] == true,
        maxOpenPositions: json['maxOpenPositions'] == true,
        exposureLimit: json['exposureLimit'] == true,
        accountEquityThreshold: json['accountEquityThreshold'] == true,
      );
}

/// Configuration for risk limits applied per-account and per-symbol.
class RiskLimits {
  final int maxContractsPerSymbol;
  final double maxDailyLoss;
  final int maxOpenPositions;
  final double maxExposurePerSymbol;
  final double minAccountEquity;
  final double minPositionSize;
  final double maxPositionSize;
  final double autoTakeProfitPercent;
  final double autoStopLossPercent;
  final Duration maxHoldTime;
  final Duration staleThreshold;

  const RiskLimits({
    this.maxContractsPerSymbol = 5,
    this.maxDailyLoss = 500.0,
    this.maxOpenPositions = 10,
    this.maxExposurePerSymbol = 5000.0,
    this.minAccountEquity = 100.0,
    this.minPositionSize = 0.01,
    this.maxPositionSize = 1.0,
    this.autoTakeProfitPercent = 50.0,
    this.autoStopLossPercent = 25.0,
    this.maxHoldTime = const Duration(hours: 24),
    this.staleThreshold = const Duration(minutes: 30),
  });

  Map<String, dynamic> toJson() => {
        'maxContractsPerSymbol': maxContractsPerSymbol,
        'maxDailyLoss': maxDailyLoss,
        'maxOpenPositions': maxOpenPositions,
        'maxExposurePerSymbol': maxExposurePerSymbol,
        'minAccountEquity': minAccountEquity,
        'minPositionSize': minPositionSize,
        'maxPositionSize': maxPositionSize,
        'autoTakeProfitPercent': autoTakeProfitPercent,
        'autoStopLossPercent': autoStopLossPercent,
        'maxHoldTimeHours': maxHoldTime.inHours,
        'staleThresholdMinutes': staleThreshold.inMinutes,
      };

  factory RiskLimits.fromJson(Map<String, dynamic> json) => RiskLimits(
        maxContractsPerSymbol: (json['maxContractsPerSymbol'] as num?)?.toInt() ?? 5,
        maxDailyLoss: (json['maxDailyLoss'] as num?)?.toDouble() ?? 500.0,
        maxOpenPositions: (json['maxOpenPositions'] as num?)?.toInt() ?? 10,
        maxExposurePerSymbol: (json['maxExposurePerSymbol'] as num?)?.toDouble() ?? 5000.0,
        minAccountEquity: (json['minAccountEquity'] as num?)?.toDouble() ?? 100.0,
        minPositionSize: (json['minPositionSize'] as num?)?.toDouble() ?? 0.01,
        maxPositionSize: (json['maxPositionSize'] as num?)?.toDouble() ?? 1.0,
        autoTakeProfitPercent: (json['autoTakeProfitPercent'] as num?)?.toDouble() ?? 50.0,
        autoStopLossPercent: (json['autoStopLossPercent'] as num?)?.toDouble() ?? 25.0,
        maxHoldTime: Duration(hours: (json['maxHoldTimeHours'] as num?)?.toInt() ?? 24),
        staleThreshold: Duration(minutes: (json['staleThresholdMinutes'] as num?)?.toInt() ?? 30),
      );
}

/// Market-hours definition for symbol groups.
class MarketHours {
  final String symbolPattern;
  final int openHourUtc;
  final int openMinuteUtc;
  final int closeHourUtc;
  final int closeMinuteUtc;
  final bool isForex;

  const MarketHours({
    required this.symbolPattern,
    required this.openHourUtc,
    required this.openMinuteUtc,
    required this.closeHourUtc,
    required this.closeMinuteUtc,
    this.isForex = false,
  });

  bool isMarketOpen(DateTime now) {
    final currentMinute = now.hour * 60 + now.minute;
    final openMinute = openHourUtc * 60 + openMinuteUtc;
    final closeMinute = closeHourUtc * 60 + closeMinuteUtc;

    if (openMinute < closeMinute) {
      return currentMinute >= openMinute && currentMinute < closeMinute;
    } else {
      return currentMinute >= openMinute || currentMinute < closeMinute;
    }
  }
}

/// Central risk management service.
///
/// Validates trading signals against position limits, daily loss caps,
/// exposure thresholds and market-hours rules.  Can fetch live account
/// equity from the backend or fall back to cached SharedPreferences data.
class RiskManagementService extends ChangeNotifier {
  static const String _limitsCacheKey = 'risk_limits_cache';
  static const String _accountCacheKey = 'risk_account_snapshot';
  static const String _dailyPnLKeyPrefix = 'daily_pnl_';

  final String _apiUrl = EnvironmentConfig.apiUrl;
  RiskLimits _limits = const RiskLimits();
  Account? _cachedAccount;
  final List<MarketHours> _marketSchedule = _defaultMarketSchedule();

  /// Symbols blocked from trading — mirrors the backend's
  /// `DEFAULT_MT5_BLOCKED_SYMBOL_BASES` plus ZAR-linked forex pairs
  /// (GBPZAR, USDZAR, ZARJPY, etc.) and XPDUSD which historically loses money.
  static const Set<String> defaultBlockedSymbols = {
    'GBPZAR', 'GBPZARm',
    'USDZAR', 'USDZARm',
    'ZARJPY', 'ZARJPYm',
    'XPDUSD', 'XPDUSDm',
    'XPTUSD', 'XPTUSDm',
  };

  /// User-configured additional blocked symbols (loaded from backend).
  final Set<String> _userBlockedSymbols = {};

  RiskLimits get limits => _limits;
  Account? get account => _cachedAccount;
  List<MarketHours> get marketSchedule => List.unmodifiable(_marketSchedule);
  Set<String> get blockedSymbols => {...defaultBlockedSymbols, ..._userBlockedSymbols};

  static List<MarketHours> _defaultMarketSchedule() {
    return [
      MarketHours(
        symbolPattern: r'^(EUR|GBP|USD|JPY|AUD|CAD|NZD|CHF).*',
        openHourUtc: 21,
        openMinuteUtc: 0,
        closeHourUtc: 20,
        closeMinuteUtc: 0,
        isForex: true,
      ),
      MarketHours(
        symbolPattern: r'^(BTC|ETH|BTCUSD|ETHUSD).*',
        openHourUtc: 0,
        openMinuteUtc: 0,
        closeHourUtc: 23,
        closeMinuteUtc: 59,
        isForex: false,
      ),
      MarketHours(
        symbolPattern: r'^(XAU|XAG).*',
        openHourUtc: 22,
        openMinuteUtc: 0,
        closeHourUtc: 21,
        closeMinuteUtc: 0,
        isForex: false,
      ),
    ];
  }

  RiskManagementService() {
    _loadCachedLimits();
    _loadCachedAccount();
  }

  Future<void> _loadCachedLimits() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_limitsCacheKey);
      if (raw == null) return;
      final json = jsonDecode(raw) as Map<String, dynamic>;
      _limits = RiskLimits.fromJson(json);
    } catch (_) {}
  }

  Future<void> _loadCachedAccount() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_accountCacheKey);
      if (raw == null) return;
      final json = jsonDecode(raw) as Map<String, dynamic>;
      _cachedAccount = Account.fromJson(json);
    } catch (_) {}
  }

  Future<void> updateLimits(RiskLimits newLimits) async {
    _limits = newLimits;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_limitsCacheKey, jsonEncode(newLimits.toJson()));
    notifyListeners();
  }

  Future<void> refreshAccountSnapshot() async {
    final prefs = await SharedPreferences.getInstance();
    final sessionToken = prefs.getString('auth_token');
    if (sessionToken == null || sessionToken.isEmpty) return;

    try {
      final response = await http
          .get(
            Uri.parse('$_apiUrl/api/account/info'),
            headers: {
              'Content-Type': 'application/json',
              'X-Session-Token': sessionToken,
            },
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        if (data['success'] == true && data['account'] != null) {
          _cachedAccount = Account.fromJson(
            Map<String, dynamic>.from(data['account'] as Map),
          );
          await prefs.setString(_accountCacheKey, jsonEncode(_cachedAccount!.toJson()));
          notifyListeners();
        }
      }
    } catch (e) {
      debugPrint('RiskManagementService: account refresh failed: $e');
    }
  }

  /// Checks whether the market is currently open for the given symbol.
  /// Falls back to *open* when no schedule entry matches.
  bool isMarketOpen(String symbol) {
    final upper = symbol.toUpperCase();
    for (final market in _marketSchedule) {
      if (RegExp(market.symbolPattern).hasMatch(upper)) {
        return market.isMarketOpen(DateTime.now().toUtc());
      }
    }
    return true;
  }

  /// Check whether a symbol is blocked from trading.
  /// Normalises the symbol (strips '/', uppercases, removes trailing 'M')
  /// so that e.g. "XPDUSDm" and "XPD/USD" both match.
  bool isSymbolBlocked(String symbol) {
    final normalised = _normaliseSymbolBase(symbol);
    for (final blocked in blockedSymbols) {
      final blockedNorm = _normaliseSymbolBase(blocked);
      if (blockedNorm == normalised) return true;
    }
    return false;
  }

  static String _normaliseSymbolBase(String symbol) {
    var s = symbol.toUpperCase().replaceAll('/', '').trim();
    if (s.endsWith('M') && s.length > 1) {
      s = s.substring(0, s.length - 1);
    }
    return s;
  }

  /// Load user-specific blocked symbols from the backend.
  Future<void> loadUserBlockedSymbols() async {
    final prefs = await SharedPreferences.getInstance();
    final sessionToken = prefs.getString('auth_token');
    if (sessionToken == null || sessionToken.isEmpty) return;

    try {
      final response = await http
          .get(
            Uri.parse('$_apiUrl/api/risk/blocked-symbols'),
            headers: {
              'Content-Type': 'application/json',
              'X-Session-Token': sessionToken,
            },
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        if (data['success'] == true) {
           final blocked = data['blockedSymbols'] as List? ?? [];
          _userBlockedSymbols
            ..clear()
            ..addAll(blocked.map((e) => e.toString().toUpperCase().trim()));
          notifyListeners();
        }
      }
    } catch (e) {
      debugPrint('RiskManagementService: failed to load blocked symbols: $e');
    }
  }

  /// Dynamic position sizing — mirrors the backend's
  /// `DynamicPositionSizer.calculate_position_size()`.
  ///
  /// Factors:
  /// - Base position size from bot config
  /// - Equity scaling (scale up to 1.5x based on cumulative profit)
  /// - Win/loss streak scaling
  /// - Performance multiplier (from symbol verdict)
  /// - Volatility adjustment
  /// - Drawdown protection
  /// - Small-account balance scaling
  /// - Min/max constraints
  static double calculatePositionSize({
    required double baseSize,
    required double minSize,
    required double maxSize,
    required int totalTrades,
    required double totalProfit,
    required double peakProfit,
    required double maxDrawdown,
    required int winStreak,
    required int lossStreak,
    required double performanceMultiplier,
    required String volatilityLevel,
    required String managementProfile,
    required double accountBalance,
  }) {
    var size = baseSize > 0 ? baseSize : 1.0;
    size = size < minSize ? minSize : size;

    // 1. Equity scaling — +10% size per $1000 profit, capped at 1.5x
    if (totalTrades > 0 && totalProfit > 0) {
      final equityMultiplier = 1.0 + (totalProfit / 1000.0);
      size *= equityMultiplier < 1.5 ? equityMultiplier : 1.5;
    }

    // 2. Win/loss streak scaling
    if (winStreak > 2) {
      size *= 1.0 + (winStreak * 0.1); // +10% per win in streak
    } else if (lossStreak >= 2) {
      size *= math.max(0.45, 1.0 - (lossStreak * 0.15));
    }

    // 3. Performance multiplier (from backend symbol verdict)
    size *= performanceMultiplier;

    // 4. Volatility adjustment
    final volatilityMultiplier = {
      'Very Low': 1.15,
      'Low': 1.1,
      'Medium': 1.0,
      'High': 0.8,
      'Very High': 0.6,
    };
    size *= volatilityMultiplier[volatilityLevel] ?? 1.0;

    // 5. Drawdown protection
    if (peakProfit > 0 && maxDrawdown > 0) {
      final drawdownPercent = (maxDrawdown / peakProfit) * 100;
      if (drawdownPercent > 20) {
        size *= 0.5;
      } else if (drawdownPercent > 10) {
        size *= 0.7;
      }
    }

    // 6. Small-account scaling
    if (_normalizeManagementProfile(managementProfile) == 'small_account') {
      if (accountBalance > 0) {
        final balanceScale = math.max(0.25, math.min(accountBalance / 250.0, 0.75));
        size *= balanceScale;
      }
      // Cap max size for small accounts
      return math.max(minSize, math.min(size, math.min(maxSize, 0.5)));
    }

    // 7. Apply min/max constraints
    return math.max(minSize, math.min(size, maxSize));
  }

  static String _normalizeManagementProfile(String? profile) {
    final p = (profile ?? '').trim().toLowerCase();
    switch (p) {
      case 'small_account':
        return 'small_account';
      case 'fast_growth':
        return 'fast_growth';
      case 'balanced':
        return 'balanced';
      case 'beginner':
        return 'beginner';
      default:
        return 'balanced';
    }
  }

  /// Per-symbol defensive scaling — mirrors the backend's
  static double applyPerSymbolDefensiveScaling({
    required String symbol,
    required double basePositionSize,
    required double symbolProfit,
    required double totalProfit,
    double lossThreshold = -20.0,
  }) {
    if (symbolProfit < lossThreshold ||
        (symbolProfit < 0 && totalProfit < 50.0)) {
      debugPrint('🛡️ Per-symbol defensive scaling: $symbol P&L=R${symbolProfit.toStringAsFixed(2)}, '
          'forcing 0.01 lot minimum');
      return math.max(0.01, basePositionSize * 0.01);
    }
    return basePositionSize;
  }

  /// Profit-tier scaling multipliers — mirrors the backend's
  /// `_PROFIT_SCALE_TIERS` and `_get_profit_scale_multipliers()`.
  ///
  /// When the bot is in profit (realized P&L > 0), the trade amount
  /// and stop-loss width (ATR) are scaled up by these tiers.
  static const List<_ProfitScaleTier> _profitScaleTiers = [
    _ProfitScaleTier(minPctOfBalance: 70.0, tradeAmountMult: 10.0, atrMult: 25.0),
    _ProfitScaleTier(minPctOfBalance: 40.0, tradeAmountMult: 7.5, atrMult: 15.0),
    _ProfitScaleTier(minPctOfBalance: 20.0, tradeAmountMult: 5.0, atrMult: 8.0),
    _ProfitScaleTier(minPctOfBalance: 10.0, tradeAmountMult: 3.0, atrMult: 4.0),
    _ProfitScaleTier(minPctOfBalance: 5.0, tradeAmountMult: 2.0, atrMult: 2.0),
    _ProfitScaleTier(minPctOfBalance: 0.0, tradeAmountMult: 1.2, atrMult: 1.2),
  ];

  /// Calculate the profit-scale multiplier for the trade amount
  /// based on realized P&L as a percentage of account balance.
  /// Mirrors `_get_profit_scale_multipliers` in the backend.
  static (double tradeAmountMult, double atrMult) getProfitScaleMultipliers({
    required double realizedPnL,
    required double balance,
  }) {
    if (realizedPnL <= 0 || balance <= 0) {
      return (1.0, 1.0);
    }
    final pct = (realizedPnL / balance) * 100.0;
    for (final tier in _profitScaleTiers) {
      if (pct >= tier.minPctOfBalance) {
        return (tier.tradeAmountMult, tier.atrMult);
      }
    }
    return (1.0, 1.0);
  }

  /// Small-account trade-amount scale — mirrors
  /// `_small_account_trade_amount_scale` in the backend.
  ///
  /// Scales DOWN the base trade amount for very small accounts so that
  /// even the broker's minimum order size does not risk more than ~5%
  /// of balance.
  static double smallAccountTradeAmountScale(double balance) {
    if (balance < 200) return 0.10;
    if (balance < 500) return 0.20;
    if (balance < 2000) return 0.40;
    if (balance < 5000) return 0.70;
    return 1.00;
  }

  /// Full position-size calculation with profit-tier scaling applied.
  ///
  /// This method mirrors the backend's order-volume pipeline:
  /// 1. Calculate base position size via [calculatePositionSize]
  /// 2. Apply small-account scaling
  /// 3. Apply profit-tier scaling (when in profit)
  /// 4. Apply per-symbol defensive scaling (for losing symbols)
  ///
  /// For symbols like US30 when the account is profitable, this produces
  /// scaled-up lot sizes (e.g. 6 x 0.2 lots) based on the profit-tier
  /// multiplier, with longer holding times via the strategy engine.
  static double calculateScaledPositionSize({
    required double baseSize,
    required double minSize,
    required double maxSize,
    required int totalTrades,
    required double totalProfit,
    required double peakProfit,
    required double maxDrawdown,
    required int winStreak,
    required int lossStreak,
    required double performanceMultiplier,
    required String volatilityLevel,
    required String managementProfile,
    required double accountBalance,
    required String symbol,
    double realizedPnL = 0.0,
    double symbolPnL = 0.0,
  }) {
    // Step 1: Base position size (equity, streaks, volatility, drawdown)
    var size = calculatePositionSize(
      baseSize: baseSize,
      minSize: minSize,
      maxSize: maxSize,
      totalTrades: totalTrades,
      totalProfit: totalProfit,
      peakProfit: peakProfit,
      maxDrawdown: maxDrawdown,
      winStreak: winStreak,
      lossStreak: lossStreak,
      performanceMultiplier: performanceMultiplier,
      volatilityLevel: volatilityLevel,
      managementProfile: managementProfile,
      accountBalance: accountBalance,
    );

    // Step 2: Small-account scale-down
    final saScale = smallAccountTradeAmountScale(accountBalance);
    size *= saScale;

    // Step 3: Profit-tier scaling — when in profit, scale up
    final (taMult, _) = getProfitScaleMultipliers(
      realizedPnL: realizedPnL,
      balance: accountBalance,
    );
    size *= taMult;

    // Step 4: Per-symbol defensive scaling — if THIS symbol is losing,
    // shrink dramatically to protect the account
    size = applyPerSymbolDefensiveScaling(
      symbol: symbol,
      basePositionSize: size,
      symbolProfit: symbolPnL,
      totalProfit: realizedPnL,
    );

    return math.max(minSize, math.min(size, maxSize));
  }

  /// Record a trade P&L for the current day so daily-loss limits can be
  /// enforced locally when the backend is unreachable.
  Future<void> recordDailyPnL(String symbol, double pnl) async {
    final prefs = await SharedPreferences.getInstance();
    final today = DateTime.now().toUtc();
    final dayKey = '${today.year}-${today.month}-${today.day}';
    final fullKey = '$_dailyPnLKeyPrefix$dayKey';
    final current = (prefs.getDouble(fullKey) ?? 0.0) + pnl;
    await prefs.setDouble(fullKey, current);
  }

  Future<double> getDailyPnL() async {
    final prefs = await SharedPreferences.getInstance();
    final today = DateTime.now().toUtc();
    final dayKey = '${today.year}-${today.month}-${today.day}';
    final fullKey = '$_dailyPnLKeyPrefix$dayKey';
    return prefs.getDouble(fullKey) ?? 0.0;
  }

  Future<void> clearStaleDailyPnL() async {
    final prefs = await SharedPreferences.getInstance();
    final today = DateTime.now().toUtc();
    final currentKey = '${today.year}-${today.month}-${today.day}';
    for (final key in prefs.getKeys()) {
      if (key.startsWith(_dailyPnLKeyPrefix) && !key.endsWith(currentKey)) {
        await prefs.remove(key);
      }
    }
  }

  /// Full validation pipeline for an incoming [signal].
  ///
  /// Returns a [RiskValidationResult] describing whether the signal is
  /// approved and, if applicable, an adjusted position size.
  RiskValidationResult validateSignal(
    TradingSignal signal, {
    required List<Trade> activeTrades,
    required Account? account,
  }) {
    final flags = RiskCheckFlags();

    // 1. Contracts-per-symbol limit
    final symbolTradeCount = activeTrades.where((t) => t.symbol == signal.symbol).length;
    if (symbolTradeCount >= _limits.maxContractsPerSymbol) {
      debugPrint('MAX_CONTRACTS_PER_SYMBOL: ${signal.symbol} has '
          '$symbolTradeCount open trades, limit is ${_limits.maxContractsPerSymbol}');
      return RiskValidationResult(
        approved: false,
        rejectionReason: 'Max contracts per symbol (${_limits.maxContractsPerSymbol}) reached',
        flags: flags.copyWith(maxContractsPerSymbol: true),
      );
    }

    // 2. Global open-positions limit
    if (activeTrades.length >= _limits.maxOpenPositions) {
      debugPrint('MAX_OPEN_POSITIONS: ${activeTrades.length} open, limit '
          '${_limits.maxOpenPositions}');
      return RiskValidationResult(
        approved: false,
        rejectionReason: 'Max open positions (${_limits.maxOpenPositions}) reached',
        flags: flags.copyWith(maxOpenPositions: true),
      );
    }

    // 3. Exposure limit — total notional value of the position must not
    //    exceed the configured maximum for the symbol.
    final exposure = signal.price * (signal.positionSize ?? 1.0);
    if (exposure > _limits.maxExposurePerSymbol) {
      debugPrint('EXPOSURE_LIMIT_EXCEEDED: ${signal.symbol} exposure '
          '=${exposure.toStringAsFixed(2)} > ${_limits.maxExposurePerSymbol}');
      return RiskValidationResult(
        approved: false,
        rejectionReason: 'Exposure ${exposure.toStringAsFixed(2)} exceeds '
            'limit ${_limits.maxExposurePerSymbol}',
        flags: flags.copyWith(exposureLimit: true),
      );
    }

    // 4. Account equity threshold
    final acct = account ?? _cachedAccount;
    if (acct != null && acct.equity < _limits.minAccountEquity) {
      debugPrint('ACCOUNT_EQUITY_THRESHOLD: equity=${acct.equity} < '
          '${_limits.minAccountEquity}');
      return RiskValidationResult(
        approved: false,
        rejectionReason: 'Account equity ${acct.equity} below minimum '
            '${_limits.minAccountEquity}',
        flags: flags.copyWith(accountEquityThreshold: true),
      );
    }

    // 6. Daily loss limit (async-safe via separate method, but check here too)
    //    We can't do async in this method, so the caller should use
    //    [checkDailyLossLimit] separately before calling validateSignal.

    return RiskValidationResult(
      approved: true,
      adjustedPositionSize: signal.positionSize,
      flags: flags,
    );
  }

  /// Async companion that checks whether the daily loss limit has been
  /// breached.  [dailyTrades] is the list of all trades closed today.
  Future<RiskValidationResult> checkDailyLossLimit({
    required List<Trade> dailyTrades,
    required double dailyLossTolerance,
  }) async {
    final dailyPnL = _sumClosedTradePnL(dailyTrades);
    if (dailyPnL < -dailyLossTolerance.abs()) {
      debugPrint('DAILY_LOSS_LIMIT: P&L=$dailyPnL < -$dailyLossTolerance');
      return RiskValidationResult(
        approved: false,
        rejectionReason: 'Daily loss limit exceeded: $dailyPnL',
        flags: const RiskCheckFlags(dailyLossLimit: true),
      );
    }

    final cachedPnL = await getDailyPnL();
    final totalLoss = dailyPnL + cachedPnL;
    if (totalLoss < -_limits.maxDailyLoss.abs()) {
      debugPrint('DAILY_LOSS_LIMIT_TOTAL: total=$totalLoss '
          'limit=-${_limits.maxDailyLoss}');
      return RiskValidationResult(
        approved: false,
        rejectionReason: 'Total daily loss limit exceeded: ${totalLoss.toStringAsFixed(2)}',
        flags: const RiskCheckFlags(dailyLossLimit: true),
      );
    }

    return const RiskValidationResult(approved: true);
  }

  double _sumClosedTradePnL(List<Trade> trades) {
    var sum = 0.0;
    for (final trade in trades) {
      if (trade.status == TradeStatus.closed) {
        sum += trade.profit ?? 0.0;
      }
    }
    return sum;
  }

  /// Result of evaluating auto-exit rules for a single open trade.
  bool shouldAutoExit(Trade trade) {
    if (trade.status != TradeStatus.open) return false;

    final now = DateTime.now();
    final age = now.difference(trade.openedAt);

    // 1. Profit target reached
    if (trade.profitPercentage != null &&
        trade.profitPercentage! >= _limits.autoTakeProfitPercent) {
      debugPrint('AUTO-EXIT: ${trade.symbol} hit take-profit threshold '
          '${_limits.autoTakeProfitPercent}% (current: ${trade.profitPercentage}%)');
      return true;
    }

    // 2. Stop-loss triggered
    if (trade.profitPercentage != null &&
        trade.profitPercentage! <= -_limits.autoStopLossPercent) {
      debugPrint('AUTO-EXIT: ${trade.symbol} hit stop-loss threshold '
          '${_limits.autoStopLossPercent}% (current: ${trade.profitPercentage}%)');
      return true;
    }

    // 3. Max hold time exceeded
    if (age > _limits.maxHoldTime) {
      debugPrint('AUTO-EXIT: ${trade.symbol} exceeded max hold time '
          '${_limits.maxHoldTime.inHours}h (open ${age.inHours}h)');
      return true;
    }

    // 4. Stale position (P&L unchanged for threshold)
    if (_isStale(trade, now)) {
      debugPrint('AUTO-EXIT: ${trade.symbol} P&L unchanged for '
          '${_limits.staleThreshold.inMinutes}min (profit: \$${trade.profit})');
      return true;
    }

    return false;
  }

  final Map<String, _StaleTracker> _staleTrackers = {};

  bool _isStale(Trade trade, DateTime now) {
    final key = trade.id ?? '${trade.symbol}_${trade.openedAt.millisecondsSinceEpoch}';
    final tracker = _staleTrackers[key] ?? _StaleTracker();
    final currentProfit = trade.profit ?? 0.0;

    if (currentProfit != tracker.lastProfit) {
      tracker.lastProfit = currentProfit;
      tracker.lastChangeTime = now;
      _staleTrackers[key] = tracker;
      return false;
    }

    return now.difference(tracker.lastChangeTime) > _limits.staleThreshold;
  }

  /// Evaluate all open trades and return those that should be auto-exited.
  List<Trade> evaluateAllForExit(List<Trade> trades) {
    return trades.where(shouldAutoExit).toList();
  }
}

/// Module-level singleton for convenience access.
final riskManagementService = RiskManagementService();

class _StaleTracker {
  double lastProfit = 0.0;
  DateTime lastChangeTime = DateTime.now();
}

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/trade.dart';
import '../models/trading_signal.dart';
import '../utils/environment_config.dart';

/// Service responsible for emitting, persisting, and routing trading alerts.
///
/// Listens to [TradingSignal] events, creates [TradeAlert] objects, stores
/// them in a local cache, and optionally pushes them to the backend's
/// alert endpoint.
class TradeAlertService extends ChangeNotifier {
  static const String _alertCacheKey = 'trade_alerts_cache';
  static const int _maxCachedAlerts = 200;

  final String _apiUrl = EnvironmentConfig.apiUrl;
  final List<TradeAlert> _alerts = [];
  bool _isDisposed = false;

  List<TradeAlert> get alerts => List.unmodifiable(_alerts);
  List<TradeAlert> get pendingAlerts =>
      _alerts.where((a) => a.isPending).toList();
  int get pendingAlertCount => pendingAlerts.length;

  TradeAlertService() {
    _loadCachedAlerts();
  }

  Future<void> _loadCachedAlerts() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_alertCacheKey);
      if (raw == null) return;
      final decoded = jsonDecode(raw);
      if (decoded is! List) return;
      _alerts
        ..clear()
        ..addAll(
          decoded.map((e) => TradeAlert.fromJson(Map<String, dynamic>.from(e)))
        );
      notifyListeners();
    } catch (e) {
      debugPrint('TradeAlertService: failed to load cached alerts: $e');
    }
  }

  Future<void> _persistAlerts() async {
    if (_isDisposed) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final toSave = _alerts.take(_maxCachedAlerts).toList();
      await prefs.setString(_alertCacheKey, jsonEncode(toSave.map((a) => a.toJson()).toList()));
    } catch (e) {
      debugPrint('TradeAlertService: failed to persist alerts: $e');
    }
  }

  /// Emits a new trading alert from an incoming [signal].
  ///
  /// Optionally pushes the alert to the backend via POST /api/alerts.
  Future<TradeAlert?> emitAlert(
    TradingSignal signal, {
    bool pushToBackend = true,
    String? customMessage,
  }) async {
    final priority = _computePriority(signal);
    final requiresAction = signal.source == SignalSource.manual ||
        signal.source == SignalSource.machineLearning ||
        priority == AlertPriority.high;

    final alert = TradeAlert(
      signal: signal,
      status: AlertStatus.pending,
      message: customMessage ?? _defaultMessage(signal),
      priority: priority,
      requiresAction: requiresAction,
    );

    _alerts.insert(0, alert);
    if (_alerts.length > _maxCachedAlerts) {
      _alerts.removeLast();
    }

    await _persistAlerts();
    notifyListeners();

    if (pushToBackend) {
      await _pushAlertToBackend(alert);
    }

    debugPrint('🚨 Alert emitted: ${signal.symbol} ${signal.type} '
        'priority=$priority');

    return alert;
  }

  AlertPriority _computePriority(TradingSignal signal) {
    final confidence = signal.confidence ?? 0.0;
    if (confidence >= 0.9 || signal.riskRewardRatio != null && signal.riskRewardRatio! >= 3.0) {
      return AlertPriority.high;
    }
    if (confidence >= 0.7 ||
        signal.source == SignalSource.economicNews ||
        signal.source == SignalSource.machineLearning) {
      return AlertPriority.normal;
    }
    return AlertPriority.low;
  }

  String _defaultMessage(TradingSignal signal) {
    final direction = switch (signal.type) {
      SignalType.buy => 'BUY',
      SignalType.sell => 'SELL',
      SignalType.close => 'CLOSE',
    };
    final confidenceStr = signal.confidence != null
        ? ' (confidence: ${(signal.confidence! * 100).toStringAsFixed(0)}%)'
        : '';
    return '$direction signal for ${signal.symbol} @ ${signal.price}$confidenceStr';
  }

  Future<void> _pushAlertToBackend(TradeAlert alert) async {
    final prefs = await SharedPreferences.getInstance();
    final sessionToken = prefs.getString('auth_token');
    if (sessionToken == null || sessionToken.isEmpty) {
      debugPrint('TradeAlertService: no session token, skipping backend push');
      return;
    }

    try {
      final response = await http
          .post(
            Uri.parse('$_apiUrl/api/alerts'),
            headers: {
              'Content-Type': 'application/json',
              'X-Session-Token': sessionToken,
            },
            body: jsonEncode(alert.toJson()),
          )
          .timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        debugPrint('TradeAlertService: alert pushed to backend');
      } else {
        debugPrint('TradeAlertService: backend push failed '
            '(${response.statusCode})');
      }
    } catch (e) {
      debugPrint('TradeAlertService: backend push error: $e');
    }
  }

  /// Acknowledge an alert by ID.
  Future<void> acknowledgeAlert(String alertId) async {
    final index = _alerts.indexWhere((a) => a.id == alertId);
    if (index == -1) return;

    _alerts[index] = _alerts[index].copyWith(
      status: AlertStatus.acknowledged,
      acknowledgedAt: DateTime.now(),
    );
    await _persistAlerts();
    notifyListeners();
  }

  /// Mark an alert as actioned (trade was executed).
  Future<void> actionAlert(String alertId, Map<String, dynamic> result) async {
    final index = _alerts.indexWhere((a) => a.id == alertId);
    if (index == -1) return;

    _alerts[index] = _alerts[index].copyWith(
      status: AlertStatus.actioned,
      acknowledgedAt: DateTime.now(),
      actionResult: result,
    );
    await _persistAlerts();
    notifyListeners();
  }

  /// Dismiss a pending alert without taking action.
  Future<void> dismissAlert(String alertId) async {
    final index = _alerts.indexWhere((a) => a.id == alertId);
    if (index == -1) return;

    _alerts[index] = _alerts[index].copyWith(status: AlertStatus.dismissed);
    await _persistAlerts();
    notifyListeners();
  }

  /// Dismiss all pending alerts.
  Future<void> clearAll() async {
    for (var i = 0; i < _alerts.length; i++) {
      if (_alerts[i].isPending) {
        _alerts[i] = _alerts[i].copyWith(status: AlertStatus.dismissed);
      }
    }
    await _persistAlerts();
    notifyListeners();
  }

  /// Fetch recent alerts from the backend.
  Future<void> refreshFromBackend() async {
    final prefs = await SharedPreferences.getInstance();
    final sessionToken = prefs.getString('auth_token');
    if (sessionToken == null || sessionToken.isEmpty) return;

    try {
      final response = await http
          .get(
            Uri.parse('$_apiUrl/api/alerts?limit=50'),
            headers: {
              'Content-Type': 'application/json',
              'X-Session-Token': sessionToken,
            },
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        if (data['success'] == true && data['alerts'] != null) {
          final fetched = (data['alerts'] as List)
              .map((e) => TradeAlert.fromJson(Map<String, dynamic>.from(e)))
              .toList();
          _alerts
            ..clear()
            ..addAll(fetched);
          await _persistAlerts();
          notifyListeners();
        }
      }
    } catch (e) {
      debugPrint('TradeAlertService: refresh failed: $e');
    }
  }

  /// Scan [trades] for stale positions and emit alerts.
  ///
  /// A position is considered stale when its P&L has been unchanged for
  /// longer than [staleThreshold] (default 30 minutes) or when the trade
  /// has been open longer than [maxOpenDuration] (default 24 hours).
  Future<void> detectStalePositions(
    List<Trade> trades, {
    Duration staleThreshold = const Duration(minutes: 30),
    Duration maxOpenDuration = const Duration(hours: 24),
  }) async {
    final now = DateTime.now();
    final openTrades = trades.where((t) => t.status == TradeStatus.open).toList();

    for (final trade in openTrades) {
      final openedAt = trade.openedAt;
      if (openedAt == null) continue;

      // Stale P&L detection
      final profit = trade.profit ?? 0.0;
      final lastCheckKey = 'stale_${trade.id}_profit';
      final lastCheckTimeKey = 'stale_${trade.id}_time';
      final prefs = await SharedPreferences.getInstance();
      final lastProfit = prefs.getDouble(lastCheckKey);
      final lastCheckTimeStr = prefs.getString(lastCheckTimeKey);

      if (lastProfit == profit && lastProfit != null) {
        final lastCheckTime = lastCheckTimeStr != null
            ? DateTime.tryParse(lastCheckTimeStr)
            : null;
        if (lastCheckTime != null && now.difference(lastCheckTime) > staleThreshold) {
          final age = now.difference(openedAt);
          await emitAlert(
            TradingSignal(
              symbol: trade.symbol,
              type: SignalType.close,
              source: SignalSource.machineLearning,
              confidence: 0.3,
              price: trade.entryPrice ?? 0,
            ),
            customMessage: 'Position ${trade.symbol} P&L unchanged for '
                '${lastCheckTime != null ? (now.difference(lastCheckTime).inMinutes).toString() : '?'} '
                'minutes (profit: \$${profit.toStringAsFixed(2)}, age: ${age.inHours}h ${age.inMinutes % 60}m)',
            pushToBackend: true,
          );
        }
      } else {
        await prefs.setDouble(lastCheckKey, profit);
        await prefs.setString(lastCheckTimeKey, now.toIso8601String());
      }

      // Max open duration detection
      if (now.difference(openedAt) > maxOpenDuration) {
        await emitAlert(
          TradingSignal(
            symbol: trade.symbol,
            type: SignalType.close,
            source: SignalSource.machineLearning,
            confidence: 0.4,
            price: trade.entryPrice ?? 0,
          ),
          customMessage: 'Position ${trade.symbol} open for '
              '${now.difference(openedAt).inHours} hours — exceeds max open duration',
          pushToBackend: true,
        );
      }
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    super.dispose();
  }
}

final tradeAlertService = TradeAlertService();

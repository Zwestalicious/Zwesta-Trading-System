import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/bot_model.dart';
import '../models/trade.dart';
import '../models/trading_signal.dart';
import '../models/account.dart';
import '../services/risk_management_service.dart';
import '../services/trade_alert_service.dart';
import '../utils/environment_config.dart';

class BotService extends ChangeNotifier {
  BotService() {
    _apiUrl = EnvironmentConfig.apiUrl;
    // Initialize lazily when needed, not in constructor
    debugPrint('🔧 BotService initialized');
    debugPrint('🌐 API URL: $_apiUrl');
    debugPrint('📱 Environment: ${EnvironmentConfig.currentEnvironment}');
    _checkBackendConnection();
  }
  Bot? _bot;
  BotStats? _stats;
  BotBilling? _billing;
  bool _isLoading = false;
  bool _isConnected = false;
  String? _errorMessage;
  String? _apiUrl;
  List<Map<String, dynamic>> _activeBots = [];
  List<Trade> _activeTrades = [];
  final Map<String, DateTime> _lastTradeBySymbol = {};
  RiskManagementService? _riskService;
  TradeAlertService? _alertService;
  SharedPreferences? _prefs;
  Timer? _pollTimer;
  bool _authPollingDisabled = false;
  DateTime? _lastFetchAt;
  String? _lastTradingMode;
  Future<void>? _inFlightFetch;
  int _consecutiveEmptyPayloads = 0;
  int _consecutiveFetchErrors = 0;
  int _winStreak = 0;
  int _lossStreak = 0;

  Bot? get bot => _bot;
  BotStats? get stats => _stats;
  BotBilling? get billing => _billing;
  bool get isLoading => _isLoading;
  bool get isConnected => _isConnected;
  String? get errorMessage => _errorMessage;
  List<Map<String, dynamic>> get activeBots => _activeBots;
  List<Trade> get activeTrades => List.unmodifiable(_activeTrades);
  Map<String, DateTime> get lastTradeBySymbol => Map.unmodifiable(_lastTradeBySymbol);

  void attachRiskService(RiskManagementService service) {
    _riskService = service;
  }

  void attachAlertService(TradeAlertService service) {
    _alertService = service;
  }

  Future<SharedPreferences> _getPrefs() async {
    _prefs ??= await SharedPreferences.getInstance();
    return _prefs!;
  }

  String _activeBotsCacheKey(SharedPreferences prefs) {
    final userId = (prefs.getString('user_id') ?? '').trim();
    return userId.isEmpty ? 'active_bots' : 'active_bots_$userId';
  }

  Future<void> _hydrateCachedActiveBotsIfNeeded(SharedPreferences prefs) async {
    if (_activeBots.isNotEmpty) {
      return;
    }

    try {
      final rawSnapshot = prefs.getString(_activeBotsCacheKey(prefs));
      if (rawSnapshot == null || rawSnapshot.trim().isEmpty) {
        return;
      }

      final lastSyncStr = prefs.getString('last_bot_sync');
      if (lastSyncStr != null) {
        final lastSync = DateTime.tryParse(lastSyncStr);
        if (lastSync != null &&
            DateTime.now().difference(lastSync) > const Duration(hours: 2)) {
          debugPrint('Cached bot snapshot is stale (>2h old), ignoring');
          return;
        }
      }

      final decoded = jsonDecode(rawSnapshot);
      if (decoded is! List || decoded.isEmpty) {
        return;
      }

      _activeBots = List<Map<String, dynamic>>.from(decoded);
      notifyListeners();
    } catch (e) {
      debugPrint('Failed to hydrate cached bots: $e');
    }
  }

  Future<void> _persistActiveBotsCache(SharedPreferences prefs, List<Map<String, dynamic>> bots) async {
    try {
      final cacheKey = _activeBotsCacheKey(prefs);
      if (bots.isEmpty) {
        await prefs.remove(cacheKey);
        return;
      }
      await prefs.setString(cacheKey, jsonEncode(bots));
      await prefs.setString('last_bot_sync', DateTime.now().toIso8601String());
    } catch (e) {
      debugPrint('Failed to persist bot cache: $e');
    }
  }

  void startPolling({String? tradingMode, Duration interval = const Duration(seconds: 2)}) {
    final mode = tradingMode ?? _lastTradingMode;
    _pollTimer?.cancel();
    // Don't skip polling due to auth state - let _fetchActiveBotsInternal handle auth errors
    _pollTimer = Timer.periodic(interval, (_) {
      fetchActiveBots(tradingMode: mode);
      fetchActiveTrades();
      _checkAutoExits();
    });
  }

  void stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  /// Evaluate auto-exit rules and emit alerts for positions that should close.
  void _checkAutoExits() {
    if (_riskService == null || _activeTrades.isEmpty) return;

    final toExit = _riskService!.evaluateAllForExit(
      _activeTrades.where((t) => t.status == TradeStatus.open).toList(),
    );

    for (final trade in toExit) {
      debugPrint('AUTO-EXIT: ${trade.symbol} trade ${trade.id} flagged for exit');
      _alertService?.emitAlert(
        TradingSignal(
          symbol: trade.symbol,
          type: SignalType.close,
          source: SignalSource.machineLearning,
          confidence: 0.5,
          price: trade.entryPrice ?? 0,
        ),
        customMessage: 'Auto-exit: ${trade.symbol} ${trade.profitPercentage != null ? 'P&L ${trade.profitPercentage}% ' : ''}(profit: \$${trade.profit?.toStringAsFixed(2) ?? '0.00'})',
        pushToBackend: true,
      );
    }
  }

  // Fallback list for Exness / MT5 symbols when backend data is not yet loaded.
  final List<String> availableTradingSymbols = [
    'BTCUSD', // Bitcoin / USD
    'ETHUSD', // Ethereum / USD
    'EURUSD', // Euro / USD
    'USDJPY', // USD / Japanese Yen
    'XAUUSD', // Gold / USD
    'AAPL',
    'AMD',
    'MSFT',
    'NVDA',
    'JPM',
    'BAC',
    'WFC',
    'GOOGL',
    'META',
    'ORCL',
    'TSM',
  ];

  final List<String> availableStrategies = [
    'Scalping',
    'Momentum Trading',
    'Trend Following',
    'EMA Pullback ML',
    'Mean Reversion',
    'Range Trading',
    'Breakout Trading'
  ];

  /// Check if backend is available
  Future<void> _checkBackendConnection() async {
    try {
      debugPrint('🔄 Checking backend connection to: $_apiUrl/api/health');
      final response = await http
          .get(
            Uri.parse('$_apiUrl/api/health'),
          )
          .timeout(const Duration(seconds: 10));

      _isConnected = response.statusCode == 200;
      if (_isConnected) {
        debugPrint('✅ Backend connected successfully');
        debugPrint('📊 Response: ${response.body}');
      } else {
        _errorMessage =
            'Backend connection failed: HTTP ${response.statusCode}';
        debugPrint('❌ Backend health check failed: ${response.statusCode}');
        debugPrint('📄 Response: ${response.body}');
      }
      notifyListeners();
    } catch (e) {
      _isConnected = false;
      _errorMessage = 'Cannot connect to backend: $e';
      debugPrint('❌ Backend connection error: $e');
      notifyListeners();
    }
  }

  /// Fetch active bots from backend
  Future<void> fetchActiveBots({String? tradingMode, bool force = false, bool includeHistory = false}) async {
    if (_inFlightFetch != null && !force) {
      return _inFlightFetch!;
    }

    final future = _fetchActiveBotsInternal(
      tradingMode: tradingMode,
      force: force,
      includeHistory: includeHistory,
    );
    _inFlightFetch = future;
    try {
      await future;
    } finally {
      if (identical(_inFlightFetch, future)) {
        _inFlightFetch = null;
      }
    }
  }

  Future<void> _fetchActiveBotsInternal({String? tradingMode, bool force = false, bool includeHistory = false}) async {
    final prefs = await _getPrefs();
    final storedMode = (prefs.getString('trading_mode') ?? '').trim().toUpperCase();
    final fallbackMode = (prefs.getBool('is_live_mode') ?? false) ? 'LIVE' : 'DEMO';
    final mode = tradingMode ?? (storedMode == 'LIVE' || storedMode == 'DEMO' ? storedMode : fallbackMode);
    await _hydrateCachedActiveBotsIfNeeded(prefs);
    final now = DateTime.now();
    if (!force && _lastFetchAt != null && _lastTradingMode == mode && now.difference(_lastFetchAt!) < const Duration(seconds: 1)) {
      return;
    }

    final previousBots = List<Map<String, dynamic>>.from(_activeBots);
    final previousError = _errorMessage;
    final shouldShowLoading = _activeBots.isEmpty;

    _isLoading = shouldShowLoading;
    _errorMessage = null;
    if (shouldShowLoading || previousError != null) {
      notifyListeners();
    }

    try {
      if (!_isConnected) {
        await _checkBackendConnection();
      }

      // Get user_id from SharedPreferences
      final userId = prefs.getString('user_id');
      final sessionToken = prefs.getString('auth_token');
      _lastTradingMode = mode;

      // Avoid hammering protected endpoints without auth header.
      // Let future requests retry - don't permanently disable polling
      if (sessionToken == null || sessionToken.isEmpty) {
        _isLoading = false;
        _errorMessage = 'Session token missing. Please login again.';
        notifyListeners();
        return;
      }

      final modeParam = mode.trim().toUpperCase();
      // Always fetch BOTH demo and live bots so the dashboard can show every
      // active bot regardless of the app's global trading_mode switcher. The
      // per-card LIVE/DEMO badge (not the global filter) distinguishes them,
      // and the dashboard applies its own mode filter client-side when needed.
      final summaryMode = 'ALL';
      var url = '$_apiUrl/api/bot/summary?mode=$summaryMode&include_broker_snapshots=true';
      if (includeHistory) {
        url += '&include_history=true';
      }
      if (userId != null && userId.isNotEmpty) {
        url += '&user_id=$userId';
      }

      final response = await http.get(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'X-Session-Token': sessionToken,
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        _authPollingDisabled = false; // Reset on successful fetch
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          final fetchedBots = List<Map<String, dynamic>>.from(data['bots'] ?? []);
          if (fetchedBots.isEmpty) {
            _consecutiveEmptyPayloads += 1;
            if (_consecutiveEmptyPayloads < 2 && previousBots.isNotEmpty) {
              debugPrint('Ignoring transient empty bot payload during refresh');
              _isLoading = false;
              return;
            }
            _consecutiveEmptyPayloads = 0;
          } else {
            _consecutiveEmptyPayloads = 0;
          }

          _activeBots = fetchedBots;
          _lastFetchAt = now;
          _errorMessage = null;
          _consecutiveFetchErrors = 0;
          debugPrint('Fetched ${_activeBots.length} active bots from backend');
          await _persistActiveBotsCache(prefs, _activeBots);
        } else {
          _errorMessage = data['error'] ?? 'Failed to fetch bots';
          // Preserve previous bot data when the backend returns a logical error.
        }
      } else {
        _errorMessage = 'Backend returned status ${response.statusCode}';
        // Don't wipe _activeBots - preserve previous data on transient error,
        // but mark the cache stale so it expires on next init.
      }
    } catch (e) {
      _errorMessage = 'Error fetching bots: $e';
      _consecutiveFetchErrors += 1;
      debugPrint('Bot fetch error: $e');
    }

    if (_consecutiveFetchErrors >= 5) {
      debugPrint('Clearing stale bot cache after $_consecutiveFetchErrors consecutive errors');
      _activeBots = [];
      await _persistActiveBotsCache(prefs, []);
      _consecutiveFetchErrors = 0;
    }

    _isLoading = false;
    if (!_botListsEqual(previousBots, _activeBots) || previousError != _errorMessage || shouldShowLoading) {
      notifyListeners();
    }
  }

  bool _botListsEqual(List<Map<String, dynamic>> first, List<Map<String, dynamic>> second) {
    if (identical(first, second)) {
      return true;
    }
    if (first.length != second.length) {
      return false;
    }

    for (var index = 0; index < first.length; index++) {
      if (jsonEncode(first[index]) != jsonEncode(second[index])) {
        return false;
      }
    }

    return true;
  }

  /// Create new bot on backend
  Future<bool> createBotOnBackend({
    required String botId,
    required String accountId,
    required List<String> symbols,
    required String strategy,
    required double riskPerTrade,
    required double maxDailyLoss,
    required bool enabled,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      // Get session token and user_id from SharedPreferences
      final prefs = await _getPrefs();
      final sessionToken = prefs.getString('auth_token');
      final userId = prefs.getString('user_id');
        final tradingMode =
          (prefs.getString('trading_mode') ?? 'DEMO').trim().toUpperCase();

      debugPrint('🔐 DEBUG: CreateBot - Checking session...');
      debugPrint('  All keys in SharedPreferences: ${prefs.getKeys()}');
      debugPrint('  auth_token value: $sessionToken');
      debugPrint('  auth_token is null: ${sessionToken == null}');
      debugPrint(
          "  auth_token isEmpty: ${sessionToken?.isEmpty ?? 'null object'}");
      debugPrint('  user_id: $userId');

      if (sessionToken == null || sessionToken.isEmpty) {
        _errorMessage =
            'Session expired. Please login again. Token was null or empty.';
        _isLoading = false;
        notifyListeners();
        return false;
      }

      debugPrint('✅ Token found, creating request headers...');
      final headers = {
        'Content-Type': 'application/json',
        'X-Session-Token': sessionToken,
      };
      debugPrint('📤 Headers being sent:');
      debugPrint('  Content-Type: ${headers['Content-Type']}');
      debugPrint(
          "  X-Session-Token: ${headers['X-Session-Token']?.substring(0, 20)}...");

      final requestBody = {
        'botId': botId,
        'user_id': userId,
        'credentialId': accountId,
        'mode': tradingMode == 'LIVE' ? 'live' : 'demo',
        'symbols': symbols,
        'strategy': strategy,
        'riskPerTrade': riskPerTrade,
        'maxDailyLoss': maxDailyLoss,
        'enabled': enabled,
        'autoSwitch': true,
        'dynamicSizing': true,
        'basePositionSize': 1.0,
        'autoStart': true,  // Always auto-start from this service path
      };

      debugPrint('📤 Sending bot creation request to $_apiUrl/api/bot/create');
      debugPrint('  Body: $requestBody');

      final response = await http
          .post(
            Uri.parse('$_apiUrl/api/bot/create'),
            headers: headers,
            body: jsonEncode(requestBody),
          )
          .timeout(const Duration(seconds: 120));

      debugPrint('📥 Response: ${response.statusCode}');
      debugPrint('  Body: ${response.body}');

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final responseData = jsonDecode(response.body);
        if (responseData['success'] == true) {
          final createdMode =
              ((requestBody['mode'] ?? 'demo').toString()).toUpperCase();
          await prefs.setString('trading_mode', createdMode);
          await prefs.setBool('is_live_mode', createdMode == 'LIVE');
          await prefs.setString(
            'dashboard_balance_mode',
            createdMode == 'LIVE' ? 'live' : 'demo',
          );
          _lastTradingMode = createdMode;
          await fetchActiveBots(tradingMode: createdMode, force: true);
          return true;
        }
        _errorMessage = responseData['error'] ?? 'Failed to create bot';
      } else if (response.statusCode == 401) {
        _errorMessage = 'Session expired or invalid token. Please login again.';
        debugPrint('❌ BOT CREATION 401 ERROR:');
        debugPrint('  Status: ${response.statusCode}');
        debugPrint('  Response: ${response.body}');
        debugPrint('  Token was: ${sessionToken.substring(0, 20)}...');
      } else {
        final responseData = jsonDecode(response.body);
        _errorMessage = responseData['error'] ?? 'Failed to create bot';
        debugPrint('❌ BOT CREATION ERROR (${response.statusCode}):');
        debugPrint('  Error: $_errorMessage');
        debugPrint('  Full response: ${response.body}');
      }
      return false;
    } catch (e) {
      _errorMessage = 'Error creating bot: $e';
      debugPrint('Bot creation error: $e');
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Start bot trading on backend
  Future<bool> startBotTrading(String botId) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final prefs = await _getPrefs();
      final sessionToken = prefs.getString('auth_token');

      if (sessionToken == null || sessionToken.isEmpty) {
        _errorMessage = 'Session expired. Please login again.';
        _isLoading = false;
        notifyListeners();
        return false;
      }

      final response = await http
          .post(
            Uri.parse('$_apiUrl/api/bot/start'),
            headers: {
              'Content-Type': 'application/json',
              'X-Session-Token': sessionToken,
            },
            body: jsonEncode({'botId': botId}),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          debugPrint('Bot started: $botId');
          await fetchActiveBots(force: true);
          return true;
        }
      } else if (response.statusCode == 401) {
        _errorMessage = 'Session expired. Please login again.';
      } else {
        _errorMessage =
            jsonDecode(response.body)['error'] ?? 'Failed to start bot';
      }
      return false;
    } catch (e) {
      _errorMessage = 'Error starting bot: $e';
      debugPrint('Bot start error: $e');
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Stop bot trading
  Future<bool> stopBotTrading(String botId) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final prefs = await _getPrefs();
      final sessionToken = prefs.getString('auth_token');

      if (sessionToken == null || sessionToken.isEmpty) {
        _errorMessage = 'Session expired. Please login again.';
        _isLoading = false;
        notifyListeners();
        return false;
      }

      final response = await http.post(
        Uri.parse('$_apiUrl/api/bot/stop/$botId'),
        headers: {
          'Content-Type': 'application/json',
          'X-Session-Token': sessionToken,
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          debugPrint('Bot stopped: $botId');
          await fetchActiveBots(force: true);
          return true;
        }
      } else if (response.statusCode == 401) {
        _errorMessage = 'Session expired. Please login again.';
      } else {
        _errorMessage =
            jsonDecode(response.body)['error'] ?? 'Failed to stop bot';
      }
      return false;
    } catch (e) {
      _errorMessage = 'Error stopping bot: $e';
      debugPrint('Bot stop error: $e');
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Close a specific open position for a bot.
  Future<bool> closeBotPosition(String botId, String ticket) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final prefs = await _getPrefs();
      final sessionToken = prefs.getString('auth_token');

      if (sessionToken == null || sessionToken.isEmpty) {
        _errorMessage = 'Session expired. Please login again.';
        _isLoading = false;
        notifyListeners();
        return false;
      }

      final response = await http.post(
        Uri.parse('$_apiUrl/api/bot/$botId/positions/$ticket/close'),
        headers: {
          'Content-Type': 'application/json',
          'X-Session-Token': sessionToken,
        },
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          debugPrint('Position closed: bot=$botId ticket=$ticket');
          await fetchActiveBots(force: true);
          return true;
        }
        _errorMessage = data['error']?.toString() ?? 'Failed to close position';
      } else if (response.statusCode == 401 || response.statusCode == 403) {
        _errorMessage = 'Session expired. Please login again.';
      } else {
        try {
          _errorMessage = jsonDecode(response.body)['error']?.toString() ?? 'Failed to close position';
        } catch (_) {
          _errorMessage = 'Failed to close position';
        }
      }
      return false;
    } catch (e) {
      _errorMessage = 'Error closing position: $e';
      debugPrint('Position close error: $e');
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> saveBot(Bot bot) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('bot_config', jsonEncode(bot.toJson()));
      _bot = bot;
      notifyListeners();
    } catch (e) {
      debugPrint('Error saving bot: $e');
    }
  }

  Future<void> toggleBot({required bool isActive}) async {
    if (_bot != null) {
      final updatedBot = Bot(
        id: _bot!.id,
        isActive: isActive,
        riskPerTrade: _bot!.riskPerTrade,
        riskType: _bot!.riskType,
        maxDailyLoss: _bot!.maxDailyLoss,
        tradingPairs: _bot!.tradingPairs,
        strategies: _bot!.strategies,
        createdAt: _bot!.createdAt,
        startedAt: isActive ? DateTime.now() : _bot!.startedAt,
      );
      await saveBot(updatedBot);

      // Also start/stop on backend if connected
      if (isActive) {
        await startBotTrading(_bot!.id);
      } else {
        await stopBotTrading(_bot!.id);
      }
    }
  }

  Future<void> updateRiskSettings({
    required double riskPerTrade,
    required String riskType,
    required double maxDailyLoss,
  }) async {
    if (_bot != null) {
      final updatedBot = Bot(
        id: _bot!.id,
        isActive: _bot!.isActive,
        riskPerTrade: riskPerTrade,
        riskType: riskType,
        maxDailyLoss: maxDailyLoss,
        tradingPairs: _bot!.tradingPairs,
        strategies: _bot!.strategies,
        createdAt: _bot!.createdAt,
        startedAt: _bot!.startedAt,
      );
      await saveBot(updatedBot);
    }
  }

  Future<void> updateTradingPairs(List<String> pairs) async {
    if (_bot != null) {
      final updatedBot = Bot(
        id: _bot!.id,
        isActive: _bot!.isActive,
        riskPerTrade: _bot!.riskPerTrade,
        riskType: _bot!.riskType,
        maxDailyLoss: _bot!.maxDailyLoss,
        tradingPairs: pairs,
        strategies: _bot!.strategies,
        createdAt: _bot!.createdAt,
        startedAt: _bot!.startedAt,
      );
      await saveBot(updatedBot);
    }
  }

  Future<void> updateStrategies(List<String> strategies) async {
    if (_bot != null) {
      final updatedBot = Bot(
        id: _bot!.id,
        isActive: _bot!.isActive,
        riskPerTrade: _bot!.riskPerTrade,
        riskType: _bot!.riskType,
        maxDailyLoss: _bot!.maxDailyLoss,
        tradingPairs: _bot!.tradingPairs,
        strategies: strategies,
        createdAt: _bot!.createdAt,
        startedAt: _bot!.startedAt,
      );
      await saveBot(updatedBot);
    }
  }

  /// Remove a bot from the active bots list locally
  void removeBotLocally(String botId) {
    _activeBots.removeWhere((bot) => (bot['botId'] ?? bot['id']) == botId);
    notifyListeners();
  }

  Future<bool> deleteBot(String botId) async {
    try {
      final prefs = await _getPrefs();
      final sessionToken = prefs.getString('auth_token');
      final userId = prefs.getString('user_id');

      if (sessionToken == null || sessionToken.isEmpty) {
        _errorMessage = 'Session expired. Please login again.';
        notifyListeners();
        return false;
      }

      final response = await http.post(
        Uri.parse('$_apiUrl/api/bot/delete/$botId'),
        headers: {
          'Content-Type': 'application/json',
          'X-Session-Token': sessionToken,
        },
        body: jsonEncode({
          if (userId != null && userId.isNotEmpty) 'user_id': userId,
        }),
      ).timeout(const Duration(seconds: 60));

      // Add null safety for response body
      if (response.body.isEmpty) {
        _errorMessage = 'Server returned empty response';
        notifyListeners();
        return false;
      }

      // Try to parse JSON with error handling
      Map<String, dynamic>? data;
      try {
        data = jsonDecode(response.body) as Map<String, dynamic>?;
      } catch (parseError) {
        _errorMessage = 'Server returned invalid response: ${response.body}';
        notifyListeners();
        return false;
      }

      // Check if data is null
      if (data == null) {
        _errorMessage = 'Server returned null data';
        notifyListeners();
        return false;
      }

      if (response.statusCode == 200 && data['success'] == true) {
        removeBotLocally(botId);
        return true;
      }

      _errorMessage = data['error']?.toString() ?? 'Failed to delete bot';
      notifyListeners();
      return false;
    } catch (e) {
      _errorMessage = 'Error deleting bot: $e';
      notifyListeners();
      return false;
    }
  }

  /// Return the subset of [_activeTrades] whose symbol matches [symbol]
  /// and whose status is still [TradeStatus.open].
  List<Trade> _getActiveTradesForSymbol(String symbol) {
    return _activeTrades
        .where(
          (trade) =>
              trade.symbol == symbol && trade.status == TradeStatus.open,
        )
        .toList();
  }

  /// Delegate position-limit checks to the [RiskManagementService].
  /// Falls back to a client-side heuristic when the service is not attached.
  bool _checkPositionLimits(TradingSignal signal, {double? positionSize}) {
    final riskService = _riskService;
    if (riskService != null) {
      // Build a signal copy with the computed position size so the risk
      // service's exposure check uses the adjusted lot size.
      final effectiveSignal = positionSize != null
          ? signal.copyWith(positionSize: positionSize)
          : signal;
      final result = riskService.validateSignal(
        effectiveSignal,
        activeTrades: _activeTrades.where((t) => t.status == TradeStatus.open).toList(),
        account: riskService.account ?? _getCachedAccount(),
      );
      if (!result.approved) {
        debugPrint('POSITION_LIMIT_EXCEEDED: ${signal.symbol} — '
            '${result.rejectionReason}');
        return false;
      }
      return true;
    }

    // Fallback: reject if more than 3 open positions exist for the symbol.
    final symbolTrades = _getActiveTradesForSymbol(signal.symbol);
    if (symbolTrades.length >= 3) {
      debugPrint('POSITION_LIMIT_EXCEEDED: ${signal.symbol} has '
          '${symbolTrades.length} open trades (fallback limit: 3)');
      return false;
    }
    return true;
  }

  /// Check whether the market is open for [symbol].
  /// Uses [RiskManagementService.isMarketOpen] when available, otherwise
  /// returns `true` (assume open).
  bool _isMarketOpen(String symbol) {
    final riskService = _riskService;
    if (riskService != null) {
      return riskService.isMarketOpen(symbol);
    }
    return true;
  }

  Account? _getCachedAccount() {
    return null;
  }

  /// Full pre-trade validation pipeline for an incoming [signal].
  ///
  /// The checks are:
  /// 0. Symbol blocklist gate (XPDUSD, ZAR forex, user-blocked)
  /// 1. Market-hours gate
  /// 2. Duplicate-trade gate
  /// 3. Position-limit gate (with dynamic position sizing)
  /// 4. Time-based holding-timeout check for existing trades
  ///
  /// When `autoExecute` is true and all checks pass, the signal is forwarded
  /// to [TradeAlertService.emitAlert] so the user (or downstream executor)
  /// can act on it.
  Future<bool> _validateTradeConditions(
    TradingSignal signal, {
    bool autoExecute = true,
  }) async {
    // 0. Symbol blocklist gate — prevents trading XPDUSD, ZAR forex, etc.
    if (_riskService?.isSymbolBlocked(signal.symbol) ?? _isSymbolBlockedLocally(signal.symbol)) {
      debugPrint('SYMBOL_BLOCKED: ${signal.symbol} is blacklisted for trading');
      return false;
    }

    // 1. Market-hours gate
    if (!_isMarketOpen(signal.symbol)) {
      debugPrint('MARKET_CLOSED: ${signal.symbol} — signal not validated');
      return false;
    }

    // 2. Position-count gate — warn about existing trades, allow add-ons
    //    up to maxContractsPerSymbol (mirroring backend's pyramid add-on).
    //    The backend's pyramid add-on system expects multiple positions per
    //    symbol (up to maxAddons for indices, more for premium forex).
    final existingTrades = _getActiveTradesForSymbol(signal.symbol);
    if (existingTrades.isNotEmpty) {
      debugPrint('POSITION_ADDON_ALLOWED: ${signal.symbol} already has '
          '${existingTrades.length} active trades — allowing add-on within limits');
    }

    // 3. Position-limit gate (with dynamic position sizing)
    final positionSize = await _calculateAdjustedPositionSize(signal);
    if (!_checkPositionLimits(signal, positionSize: positionSize)) {
      debugPrint('POSITION_LIMIT_EXCEEDED: ${signal.symbol}');
      return false;
    }

    // 4. Time-based holding-timeout check for existing trades on other symbols
    for (final trade in _activeTrades.where((t) => t.status == TradeStatus.open)) {
      if (trade.symbol != signal.symbol &&
          DateTime.now().difference(trade.openedAt).inHours >= 8) {
        debugPrint('TRADE_TIMEOUT_HOLDING: ${trade.symbol} open for '
            '${DateTime.now().difference(trade.openedAt).inHours}h');
      }
    }

    // All checks passed — update the signal with the computed lot size
    final adjustedSignal = signal.copyWith(positionSize: positionSize);

    if (autoExecute) {
      final alertService = _alertService;
      if (alertService != null) {
        await alertService.emitAlert(adjustedSignal);
      }
    }

    // Record the last trade timestamp for this symbol
    _lastTradeBySymbol[signal.symbol] = signal.timestamp;

    return true;
  }

  static const Set<String> _localBlockedSymbols = {
    'GBPZAR', 'GBPZARm',
    'USDZAR', 'USDZARm',
    'ZARJPY', 'ZARJPYm',
    'XPDUSD', 'XPDUSDm',
    'XPTUSD', 'XPTUSDm',
  };

  bool _isSymbolBlockedLocally(String symbol) {
    final normalised = symbol.toUpperCase().replaceAll('/', '').trim();
    final withoutM = normalised.endsWith('M') && normalised.length > 1
        ? normalised.substring(0, normalised.length - 1)
        : normalised;
    return _localBlockedSymbols.contains(normalised) ||
        _localBlockedSymbols.contains(withoutM);
  }

  /// Calculate the adjusted position size for a signal, applying the
  /// backend's profit-tier scaling and per-symbol defensive scaling.
  ///
  /// Mirrors `_resolve_adaptive_trade_amount()` +
  /// `DynamicPositionSizer.calculate_position_size()` +
  /// `_evaluate_pyramid_addon()` from the backend.
  Future<double> _calculateAdjustedPositionSize(TradingSignal signal) async {
    final riskService = _riskService;
    if (riskService == null) {
      // Fallback: 0.01 lots for indices, 0.01 for forex
      return _defaultLotSize(signal.symbol);
    }

    final prefs = await _getPrefs();
    final botConfigRaw = prefs.getString('bot_config');
    Bot? savedBot;
    if (botConfigRaw != null) {
      try {
        savedBot = Bot.fromJson(jsonDecode(botConfigRaw));
      } catch (_) {}
    }

    final baseSize = savedBot?.riskPerTrade ?? 0.1;
    final symbolPnL = _symbolProfit(signal.symbol);
    final realizedPnL = _totalProfit;
    final accountBalance = riskService.account?.balance ?? 0.0;
    final limits = riskService.limits;

    // Full profit-tier sizing: equity, streaks, volatility, drawdown,
    // small-account scale, profit-tier boost, per-symbol defensive
    return RiskManagementService.calculateScaledPositionSize(
      baseSize: baseSize,
      minSize: limits.minPositionSize,
      maxSize: limits.maxPositionSize,
      totalTrades: 0,
      totalProfit: realizedPnL,
      peakProfit: 0.0,
      maxDrawdown: 0.0,
      winStreak: _winStreak,
      lossStreak: _lossStreak,
      performanceMultiplier: 1.0,
      volatilityLevel: 'Medium',
      managementProfile: 'balanced',
      accountBalance: accountBalance,
      symbol: signal.symbol,
      realizedPnL: realizedPnL,
      symbolPnL: symbolPnL,
    );
  }

  static double _defaultLotSize(String symbol) {
    final upper = symbol.toUpperCase().replaceAll('/', '');
    // US30, UK100, etc. — use smaller lots (0.01) for indices
    if (upper.contains('US30') || upper.contains('UK100') ||
        upper.contains('NAS100') || upper.contains('GER30') ||
        upper.contains('SPX500') || upper.contains('USTEC')) {
      return 0.01;
    }
    // Forex majors — standard 0.01 to 0.1 lots
    if (upper.contains('USD') || upper.contains('EUR') ||
        upper.contains('GBP') || upper.contains('JPY') ||
        upper.contains('AUD') || upper.contains('CAD') || upper.contains('CHF')) {
      return 0.01;
    }
    // Crypto — 0.001 to 0.01 lots
    return 0.001;
  }

  double get _totalProfit {
    // Approximate total profit from active trades' unrealized P&L
    var total = 0.0;
    for (final trade in _activeTrades.where((t) => t.status == TradeStatus.open)) {
      total += trade.profit ?? 0.0;
    }
    return total;
  }

  double _symbolProfit(String symbol) {
    var total = 0.0;
    for (final trade in _activeTrades.where((t) => t.symbol == symbol)) {
      total += trade.profit ?? 0.0;
    }
    return total;
  }


  /// Fetch the user's currently open trades from the backend and cache them
  /// locally in [_activeTrades].
  Future<void> fetchActiveTrades() async {
    try {
      final prefs = await _getPrefs();
      final sessionToken = prefs.getString('auth_token');
      if (sessionToken == null || sessionToken.isEmpty) {
        debugPrint('Cannot fetch active trades: no session token');
        return;
      }

      final url = '$_apiUrl/api/trades/open?mode=ALL';
      final response = await http
          .get(
            Uri.parse(url),
            headers: {
              'Content-Type': 'application/json',
              'X-Session-Token': sessionToken,
            },
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        if (data['success'] == true) {
          final tradesData = data['trades'] as List? ?? [];
          final trades = tradesData
              .map((e) => Trade.fromJson(Map<String, dynamic>.from(e)))
              .toList();
          _activeTrades = trades;
          debugPrint('Fetched ${_activeTrades.length} active trades');
        } else {
          _activeTrades = [];
          debugPrint('Backend returned success=false for trades, clearing cache');
        }
      } else {
        _activeTrades = [];
        debugPrint('Backend returned status ${response.statusCode} for trades, clearing stale cache');
      }
    } catch (e) {
      _activeTrades = [];
      debugPrint('Error fetching active trades: $e');
    }
  }

  /// Public entry point: process a received [TradingSignal] through the
  /// full validation pipeline.
  ///
  /// Returns a [RiskValidationResult] describing whether the signal was
  /// approved and (if rejected) why.
  Future<RiskValidationResult> processSignal(TradingSignal signal) async {
    final approved = await _validateTradeConditions(signal);
    return RiskValidationResult(
      approved: approved,
    );
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }
}

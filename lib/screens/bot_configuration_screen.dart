// ignore_for_file: unused_element, unused_field, unnecessary_cast, unused_local_variable

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../providers/currency_provider.dart';
import '../services/bot_service.dart';
import '../services/broker_credentials_service.dart';
import '../services/commission_service.dart';
import '../services/fund_service.dart';
import '../utils/environment_config.dart';
import '../widgets/logo_widget.dart';
import 'bot_dashboard_screen.dart';
import 'broker_integration_screen.dart';
import 'consolidated_reports_screen.dart';
import 'dashboard_screen.dart';

class BotConfigurationScreen extends StatefulWidget {
  const BotConfigurationScreen({
    Key? key,
    this.botId,
    this.cloneFromBotId,
    this.promoteToLive = false,
    this.focusTestedTemplates = false,
  }) : super(key: key);

  final String? botId;
  final String? cloneFromBotId;
  final bool promoteToLive;
  final bool focusTestedTemplates;

  @override
  State<BotConfigurationScreen> createState() => _BotConfigurationScreenState();
}

class _BotConfigurationScreenState extends State<BotConfigurationScreen> {
  final GlobalKey _testedTemplatesSectionKey = GlobalKey();
  bool get _isEditMode =>
      widget.botId != null && widget.botId!.trim().isNotEmpty;
  bool get _isCloneMode =>
      !_isEditMode &&
      widget.cloneFromBotId != null &&
      widget.cloneFromBotId!.trim().isNotEmpty;
  String get _configSourceBotId =>
      _isEditMode ? widget.botId!.trim() : widget.cloneFromBotId!.trim();

  // Volatility filter toggle
  bool _volatilityFilterEnabled = true;
  // Intelligent scanner: auto-scan all markets & reallocate to best opportunities
  bool _intelligentScanner = true;
  // Top-movers scanner: follow Binance USDT pairs with highest 24h momentum
  bool _topMoversEnabled = true;
  // Top-movers direct trading: bypass signal engine and trade momentum directly
  bool _topMoversDirectTrading = false;
  static const List<double> _tradeAmountPresets = [
    20,
    50,
    100,
    300,
    500,
    1000,
    2000,
    5000,
    10000,
    20000,
  ];

  static const List<Map<String, String>> _fxcmFallbackSymbols = [
    {'symbol': 'AUD/CNH', 'name': 'Australian Dollar vs. Offshore Chinese Yuan', 'category': 'Forex'},
    {'symbol': 'EUR/USD', 'name': 'Euro vs. US Dollar', 'category': 'Forex'},
    {
      'symbol': 'GBP/USD',
      'name': 'Great British Pound vs. US Dollar',
      'category': 'Forex',
    },
    {
      'symbol': 'USD/JPY',
      'name': 'US Dollar vs. Japanese Yen',
      'category': 'Forex',
    },
    {
      'symbol': 'AUD/USD',
      'name': 'Australian Dollar vs. US Dollar',
      'category': 'Forex',
    },
    {
      'symbol': 'EUR/JPY',
      'name': 'Euro vs. Japanese Yen',
      'category': 'Forex',
    },
    {
      'symbol': 'GBP/JPY',
      'name': 'Great British Pound vs. Japanese Yen',
      'category': 'Forex',
    },
    {
      'symbol': 'AUD/JPY',
      'name': 'Australian Dollar vs. Japanese Yen',
      'category': 'Forex',
    },
    {
      'symbol': 'CHF/JPY',
      'name': 'Swiss Franc vs. Japanese Yen',
      'category': 'Forex',
    },
    {
      'symbol': 'USD/CHF',
      'name': 'US Dollar vs. Swiss Franc',
      'category': 'Forex',
    },
    {
      'symbol': 'GBP/CHF',
      'name': 'Great British Pound vs. Swiss Franc',
      'category': 'Forex',
    },
    {
      'symbol': 'EUR/AUD',
      'name': 'Euro vs. Australian Dollar',
      'category': 'Forex',
    },
    {
      'symbol': 'EUR/CHF',
      'name': 'Euro vs. Swiss Franc',
      'category': 'Forex',
    },
    {
      'symbol': 'EUR/CAD',
      'name': 'Euro vs. Canadian Dollar',
      'category': 'Forex',
    },
    {
      'symbol': 'EUR/GBP',
      'name': 'Euro vs. Great British Pound',
      'category': 'Forex',
    },
    {
      'symbol': 'AUD/CAD',
      'name': 'Australian Dollar vs. Canadian Dollar',
      'category': 'Forex',
    },
    {
      'symbol': 'NZD/USD',
      'name': 'New Zealand Dollar vs. US Dollar',
      'category': 'Forex',
    },
    {
      'symbol': 'USD/CAD',
      'name': 'US Dollar vs. Canadian Dollar',
      'category': 'Forex',
    },
    {'symbol': 'US30', 'name': 'Dow Jones Industrial Average Cash', 'category': 'Indices'},
    {'symbol': 'GER30', 'name': 'DAX Performance Index Cash', 'category': 'Indices'},
    {'symbol': 'UK100', 'name': 'FTSE 100 Index Cash', 'category': 'Indices'},
    {'symbol': 'NAS100', 'name': 'Nasdaq Composite Cash', 'category': 'Indices'},
    {'symbol': 'SPX500', 'name': 'S&P 500 Index Cash', 'category': 'Indices'},
    {'symbol': 'Gold', 'name': 'XAU/USD Spot - Gold', 'category': 'Commodities'},
    {'symbol': 'Silver', 'name': 'XAG/USD Spot', 'category': 'Commodities'},
    {'symbol': 'USOilSpot', 'name': 'WTI Oil Spot', 'category': 'Commodities'},
    {'symbol': 'UKOilSpot', 'name': 'Brent Oil Spot', 'category': 'Commodities'},
    {'symbol': '5USNote', 'name': 'US 5-Year T-Note Future', 'category': 'Treasury'},
    {'symbol': '10USNote', 'name': 'US 10-Year T-Note Future', 'category': 'Treasury'},
    {'symbol': '2USNote', 'name': 'US 2-Year T-Note Future', 'category': 'Treasury'},
    {'symbol': 'Bobl', 'name': 'Euro Bobl Future', 'category': 'Treasury'},
    {'symbol': 'Schatz', 'name': 'Euro Schatz Future', 'category': 'Treasury'},
    {'symbol': 'FED30D', 'name': 'US 30 Day Fed Rate Future', 'category': 'Treasury'},
    {'symbol': 'EURIBOR3M', 'name': 'Euribor (3 month) Future', 'category': 'Treasury'},
    {'symbol': 'SONIA3M', 'name': 'SONIA (3 month) Future', 'category': 'Treasury'},
  ];

  static const List<String> _fxcmPreferredSymbolOrder = [
    'EUR/USD',
    'GBP/USD',
    'USD/JPY',
    'USD/CHF',
    'AUD/USD',
    'NZD/USD',
    'USD/CAD',
    'EUR/JPY',
    'GBP/JPY',
    'US30',
    'GER30',
    'NAS100',
    'SPX500',
    'Gold',
    'Silver',
    'USOilSpot',
    'UKOilSpot',
  ];

  static const List<String> _traditionalRecommendedSymbolOrder = [
    'EURUSD',
    'GBPUSD',
    'USDJPY',
    'USDCHF',
    'AUDUSD',
    'NZDUSD',
    'USDCAD',
    'EURGBP',
    'EURJPY',
    'GBPJPY',
    'USDZAR',
    'GBPZAR',
    'ZARJPY',
    'XAUUSD',
    'XAGUSD',
    'USOIL',
    'UKOIL',
    'US30',
    'US500',
    'USTEC',
    'NAS100',
    'SPX500',
    'GER30',
    'UK100',
    'BTCUSD',
    'ETHUSD',
  ];
  static const List<Map<String, String>> _binanceCoreSymbols = [
    // --- Tier 1: Large Cap ---
    {
      'symbol': 'BTCUSDT',
      'name': '₿ Bitcoin / Tether',
      'category': 'Large Cap',
    },
    {
      'symbol': 'ETHUSDT',
      'name': '◆ Ethereum / Tether',
      'category': 'Large Cap',
    },
    {'symbol': 'BNBUSDT', 'name': '◈ BNB / Tether', 'category': 'Large Cap'},
    {'symbol': 'SOLUSDT', 'name': '◎ Solana / Tether', 'category': 'Large Cap'},
    {'symbol': 'XRPUSDT', 'name': '✕ XRP / Tether', 'category': 'Large Cap'},
    {
      'symbol': 'ADAUSDT',
      'name': '◌ Cardano / Tether',
      'category': 'Large Cap',
    },
    {
      'symbol': 'DOGEUSDT',
      'name': '🐕 Dogecoin / Tether',
      'category': 'Large Cap',
    },
    {'symbol': 'TONUSDT', 'name': '◉ Toncoin / Tether', 'category': 'Large Cap'},
    {'symbol': 'XLMUSDT', 'name': '✦ Stellar / Tether', 'category': 'Large Cap'},
    // --- Tier 2: High-Volume Altcoins ---
    {
      'symbol': 'AVAXUSDT',
      'name': '▲ Avalanche / Tether',
      'category': 'Altcoin',
    },
    {
      'symbol': 'MATICUSDT',
      'name': '⬟ Polygon / Tether',
      'category': 'Altcoin',
    },
    {
      'symbol': 'LINKUSDT',
      'name': '⛓ Chainlink / Tether',
      'category': 'Altcoin',
    },
    {'symbol': 'LTCUSDT', 'name': 'Ł Litecoin / Tether', 'category': 'Altcoin'},
    {'symbol': 'BCHUSDT', 'name': 'Ƀ Bitcoin Cash / Tether', 'category': 'Altcoin'},
    {'symbol': 'ETCUSDT', 'name': 'Ξ Ethereum Classic / Tether', 'category': 'Altcoin'},
    {'symbol': 'TRXUSDT', 'name': '△ TRON / Tether', 'category': 'Altcoin'},
    {'symbol': 'DOTUSDT', 'name': '● Polkadot / Tether', 'category': 'Altcoin'},
    {'symbol': 'ATOMUSDT', 'name': '⚛ Cosmos / Tether', 'category': 'Altcoin'},
    {'symbol': 'FILUSDT', 'name': '◫ Filecoin / Tether', 'category': 'Altcoin'},
    {'symbol': 'ICPUSDT', 'name': '◎ Internet Computer / Tether', 'category': 'Altcoin'},
    {'symbol': 'HBARUSDT', 'name': 'ℏ Hedera / Tether', 'category': 'Altcoin'},
    {'symbol': 'VETUSDT', 'name': '✓ VeChain / Tether', 'category': 'Altcoin'},
    // --- Tier 3: DeFi & Layer-2 (high volatility) ---
    {
      'symbol': 'SHIBUSDT',
      'name': '🦴 Shiba Inu / Tether',
      'category': 'DeFi & L2',
    },
    {
      'symbol': 'UNIUSDT',
      'name': '🦄 Uniswap / Tether',
      'category': 'DeFi & L2',
    },
    {
      'symbol': 'NEARUSDT',
      'name': '◎ NEAR Protocol / Tether',
      'category': 'DeFi & L2',
    },
    {
      'symbol': 'ARBUSDT',
      'name': '🔵 Arbitrum / Tether',
      'category': 'DeFi & L2',
    },
    {
      'symbol': 'OPUSDT',
      'name': '🔴 Optimism / Tether',
      'category': 'DeFi & L2',
    },
    {'symbol': 'APTUSDT', 'name': '⚡ Aptos / Tether', 'category': 'DeFi & L2'},
    {
      'symbol': 'INJUSDT',
      'name': '💉 Injective / Tether',
      'category': 'DeFi & L2',
    },
    {'symbol': 'SUIUSDT', 'name': '💧 Sui / Tether', 'category': 'DeFi & L2'},
    {
      'symbol': 'FTMUSDT',
      'name': '👻 Fantom / Tether',
      'category': 'DeFi & L2',
    },
    {'symbol': 'AAVEUSDT', 'name': '👻 Aave / Tether', 'category': 'DeFi & L2'},
    {'symbol': 'SEIUSDT', 'name': '⚡ Sei / Tether', 'category': 'DeFi & L2'},
    {'symbol': 'TIAUSDT', 'name': '✧ Celestia / Tether', 'category': 'DeFi & L2'},
    {'symbol': 'JUPUSDT', 'name': '♃ Jupiter / Tether', 'category': 'DeFi & L2'},
    {'symbol': 'ENAUSDT', 'name': '⟠ Ethena / Tether', 'category': 'DeFi & L2'},
    {'symbol': 'FETUSDT', 'name': '🤖 Fetch.ai / Tether', 'category': 'DeFi & L2'},
    {'symbol': 'IMXUSDT', 'name': '🛡 Immutable / Tether', 'category': 'DeFi & L2'},
    // --- Tier 4: Gaming / Metaverse / Cross-chain ---
    {
      'symbol': 'SANDUSDT',
      'name': '🏖 The Sandbox / Tether',
      'category': 'Gaming',
    },
    {
      'symbol': 'MANAUSDT',
      'name': '🌐 Decentraland / Tether',
      'category': 'Gaming',
    },
    {
      'symbol': 'RUNEUSDT',
      'name': '⚗️ THORChain / Tether',
      'category': 'Gaming',
    },
    {'symbol': 'ALGOUSDT', 'name': '◈ Algorand / Tether', 'category': 'Gaming'},
    {'symbol': 'GALAUSDT', 'name': '🎮 Gala / Tether', 'category': 'Gaming'},
    {'symbol': 'PEPEUSDT', 'name': '🐸 Pepe / Tether', 'category': 'Meme'},
    {'symbol': 'WIFUSDT', 'name': '🧢 dogwifhat / Tether', 'category': 'Meme'},
    {'symbol': 'BONKUSDT', 'name': '🐕 Bonk / Tether', 'category': 'Meme'},
    // --- USDC stablecoin pairs (use USDC inventory) ---
    {'symbol': 'BTCUSDC', 'name': '₿ Bitcoin / USDC', 'category': 'USDC Quote'},
    {'symbol': 'ETHUSDC', 'name': '◆ Ethereum / USDC', 'category': 'USDC Quote'},
    {'symbol': 'SOLUSDC', 'name': '◎ Solana / USDC', 'category': 'USDC Quote'},
    {'symbol': 'BNBUSDC', 'name': '◈ BNB / USDC', 'category': 'USDC Quote'},
    {'symbol': 'XRPUSDC', 'name': '✕ XRP / USDC', 'category': 'USDC Quote'},
    {'symbol': 'AVAXUSDC', 'name': '▲ Avalanche / USDC', 'category': 'USDC Quote'},
    {'symbol': 'LINKUSDC', 'name': '⛓ Chainlink / USDC', 'category': 'USDC Quote'},
  ];

  static const List<Map<String, String>> _binanceQuotedAssets = [
    {'base': 'ETH', 'label': '◆ Ethereum', 'category': 'Large Cap'},
    {'base': 'BNB', 'label': '◈ BNB', 'category': 'Large Cap'},
    {'base': 'SOL', 'label': '◎ Solana', 'category': 'Large Cap'},
    {'base': 'XRP', 'label': '✕ XRP', 'category': 'Large Cap'},
    {'base': 'ADA', 'label': '◌ Cardano', 'category': 'Large Cap'},
    {'base': 'DOGE', 'label': '🐕 Dogecoin', 'category': 'Large Cap'},
    {'base': 'LINK', 'label': '⛓ Chainlink', 'category': 'Altcoin'},
    {'base': 'AVAX', 'label': '▲ Avalanche', 'category': 'Altcoin'},
    {'base': 'LTC', 'label': 'Ł Litecoin', 'category': 'Altcoin'},
    {'base': 'DOT', 'label': '● Polkadot', 'category': 'Altcoin'},
    {'base': 'ATOM', 'label': '⚛ Cosmos', 'category': 'Altcoin'},
    {'base': 'SHIB', 'label': '🦴 Shiba Inu', 'category': 'DeFi & L2'},
  ];

  static List<Map<String, String>> _buildQuotedBinanceMarkets() {
    const quoteLabels = {
      'BTC': 'Bitcoin',
      'ETH': 'Ethereum',
      'BNB': 'BNB',
    };
    const quoteOrder = ['BTC', 'ETH', 'BNB'];

    return _binanceQuotedAssets.expand((asset) {
      final base = asset['base']!;
      final label = asset['label']!;
      final category = asset['category']!;
      return quoteOrder.where((quote) => quote != base).map((quote) {
        return {
          'symbol': '$base$quote',
          'name': '$label / ${quoteLabels[quote]}',
          'category': '$category • $quote Quote',
          'analysisSymbol': '${base}USDT',
        };
      });
    }).toList();
  }

  static final List<Map<String, String>> _binanceSymbols = [
    ..._binanceCoreSymbols,
    ..._buildQuotedBinanceMarkets(),
  ];

  static const Map<String, Map<String, dynamic>> _binancePairAnalytics = {
    'BTCUSDT': {
      'edgePct': 7.5,
      'winRate': 65.0,
      'liquidityScore': 99.0,
      'risk': 'Low',
      'analysis': 'Momentum leader',
    },
    'ETHUSDT': {
      'edgePct': 7.0,
      'winRate': 63.0,
      'liquidityScore': 97.0,
      'risk': 'Low',
      'analysis': 'Trend continuation',
    },
    'BNBUSDT': {
      'edgePct': 6.0,
      'winRate': 60.0,
      'liquidityScore': 92.0,
      'risk': 'Medium',
      'analysis': 'Exchange beta',
    },
    'SOLUSDT': {
      'edgePct': 8.0,
      'winRate': 61.0,
      'liquidityScore': 90.0,
      'risk': 'Medium',
      'analysis': 'High momentum',
    },
    'XRPUSDT': {
      'edgePct': 6.5,
      'winRate': 59.0,
      'liquidityScore': 91.0,
      'risk': 'Low',
      'analysis': 'Range breakout • micro-safe',
    },
    'ADAUSDT': {
      'edgePct': 6.0,
      'winRate': 58.0,
      'liquidityScore': 86.0,
      'risk': 'Low',
      'analysis': 'Mean reversion • micro-safe',
    },
    'DOGEUSDT': {
      'edgePct': 7.2,
      'winRate': 56.0,
      'liquidityScore': 88.0,
      'risk': 'Medium',
      'analysis': 'Volatility spikes • micro-safe',
    },
    'AVAXUSDT': {
      'edgePct': 7.0,
      'winRate': 57.0,
      'liquidityScore': 82.0,
      'risk': 'High',
      'analysis': 'Momentum bursts',
    },
    'MATICUSDT': {
      'edgePct': 6.2,
      'winRate': 57.0,
      'liquidityScore': 81.0,
      'risk': 'Medium',
      'analysis': 'Swing setup • micro-safe',
    },
    'LINKUSDT': {
      'edgePct': 6.5,
      'winRate': 59.0,
      'liquidityScore': 84.0,
      'risk': 'Medium',
      'analysis': 'Trend strength',
    },
    'LTCUSDT': {
      'edgePct': 5.5,
      'winRate': 56.0,
      'liquidityScore': 78.0,
      'risk': 'Medium',
      'analysis': 'Lower beta',
    },
    'TRXUSDT': {
      'edgePct': 5.0,
      'winRate': 58.0,
      'liquidityScore': 76.0,
      'risk': 'Low',
      'analysis': 'Stable mover • micro-safe',
    },
    'DOTUSDT': {
      'edgePct': 5.8,
      'winRate': 57.0,
      'liquidityScore': 77.0,
      'risk': 'Medium',
      'analysis': 'Trend rebound',
    },
    'ATOMUSDT': {
      'edgePct': 6.0,
      'winRate': 56.0,
      'liquidityScore': 75.0,
      'risk': 'Medium',
      'analysis': 'Range expansion',
    },
    'SHIBUSDT': {
      'edgePct': 7.8,
      'winRate': 53.0,
      'liquidityScore': 80.0,
      'risk': 'High',
      'analysis': 'Speculative bursts • micro-safe',
    },
    'UNIUSDT': {
      'edgePct': 6.5,
      'winRate': 57.0,
      'liquidityScore': 72.0,
      'risk': 'High',
      'analysis': 'DeFi momentum',
    },
    'NEARUSDT': {
      'edgePct': 6.8,
      'winRate': 56.0,
      'liquidityScore': 74.0,
      'risk': 'High',
      'analysis': 'Trend acceleration',
    },
    'ARBUSDT': {
      'edgePct': 7.2,
      'winRate': 55.0,
      'liquidityScore': 76.0,
      'risk': 'High',
      'analysis': 'L2 impulse',
    },
    'OPUSDT': {
      'edgePct': 7.0,
      'winRate': 55.0,
      'liquidityScore': 75.0,
      'risk': 'High',
      'analysis': 'L2 breakout',
    },
    'APTUSDT': {
      'edgePct': 7.5,
      'winRate': 54.0,
      'liquidityScore': 73.0,
      'risk': 'High',
      'analysis': 'High beta alpha',
    },
    'INJUSDT': {
      'edgePct': 8.5,
      'winRate': 58.0,
      'liquidityScore': 71.0,
      'risk': 'High',
      'analysis': 'Strong trend alpha',
    },
    'SUIUSDT': {
      'edgePct': 7.5,
      'winRate': 55.0,
      'liquidityScore': 70.0,
      'risk': 'High',
      'analysis': 'Volatility trend',
    },
    'FTMUSDT': {
      'edgePct': 7.2,
      'winRate': 54.0,
      'liquidityScore': 68.0,
      'risk': 'High',
      'analysis': 'Fast movers',
    },
    'AAVEUSDT': {
      'edgePct': 6.5,
      'winRate': 56.0,
      'liquidityScore': 69.0,
      'risk': 'High',
      'analysis': 'DeFi trend',
    },
    'SANDUSDT': {
      'edgePct': 6.2,
      'winRate': 54.0,
      'liquidityScore': 65.0,
      'risk': 'High',
      'analysis': 'Narrative spikes',
    },
    'MANAUSDT': {
      'edgePct': 6.0,
      'winRate': 53.0,
      'liquidityScore': 64.0,
      'risk': 'High',
      'analysis': 'Event-driven',
    },
    'RUNEUSDT': {
      'edgePct': 6.8,
      'winRate': 55.0,
      'liquidityScore': 67.0,
      'risk': 'High',
      'analysis': 'Cross-chain momentum',
    },
    'ALGOUSDT': {
      'edgePct': 5.5,
      'winRate': 55.0,
      'liquidityScore': 63.0,
      'risk': 'Medium',
      'analysis': 'Range rotations',
    },
    'XLMUSDT': {
      'edgePct': 5.2,
      'winRate': 56.0,
      'liquidityScore': 74.0,
      'risk': 'Low',
      'analysis': 'Breakout pulses • micro-safe',
    },
    'HBARUSDT': {
      'edgePct': 5.0,
      'winRate': 55.0,
      'liquidityScore': 70.0,
      'risk': 'Low',
      'analysis': 'Network momentum • micro-safe',
    },
    'PEPEUSDT': {
      'edgePct': 7.8,
      'winRate': 52.0,
      'liquidityScore': 72.0,
      'risk': 'High',
      'analysis': 'Meme momentum • micro-safe',
    },
    'TONUSDT': {
      'edgePct': 5.8,
      'winRate': 56.0,
      'liquidityScore': 75.0,
      'risk': 'Medium',
      'analysis': 'Ecosystem growth • micro-safe',
    },
  };

  Future<String> _currentTradingMode() async {
    final prefs = await SharedPreferences.getInstance();
    final storedMode = (prefs.getString('trading_mode') ?? '').trim().toUpperCase();
    if (storedMode == 'LIVE' || storedMode == 'DEMO') {
      return storedMode;
    }
    return (prefs.getBool('is_live_mode') ?? false) ? 'LIVE' : 'DEMO';
  }

  Future<void> _persistTradingMode(String mode) async {
    final prefs = await SharedPreferences.getInstance();
    final normalizedMode = mode.trim().toUpperCase();
    await prefs.setString('trading_mode', normalizedMode);
    await prefs.setBool('is_live_mode', normalizedMode == 'LIVE');
    await prefs.setString(
      'dashboard_balance_mode',
      normalizedMode == 'LIVE' ? 'live' : 'demo',
    );
  }

  // Dialog to input account number
  Future<String?> _showAccountInputDialog(BuildContext context) async {
    String? account;
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Enter Destination Account'),
        content: TextField(
          decoration: const InputDecoration(hintText: 'Account Number'),
          onChanged: (value) => account = value,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    return account;
  }

  // Dialog to input amount
  Future<double?> _showAmountInputDialog(
    BuildContext context, {
    String title = 'Enter Amount',
  }) async {
    String? amountStr;
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          decoration: const InputDecoration(hintText: 'Amount'),
          keyboardType: TextInputType.number,
          onChanged: (value) => amountStr = value,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    if (amountStr == null) return null;
    final amount = double.tryParse(amountStr!);
    return amount;
  }

  late TextEditingController _botIdController;
  late TextEditingController _investmentAmountController;
  final FundService _fundService = FundService();

  List<String> _allowedVolatility = ['Very Low', 'Low'];

  // ========== NEW: Automated Risk Management Settings ==========
  double _riskPercent = 5; // Risk per trade as %
  int _maxOpenTrades = 10; // Max simultaneous trades
  double _maxDrawdownPercent = 30; // Max allowed drawdown %
  String _managementProfile = 'balanced';
  int? _manualSignalThreshold;

  String _selectedStrategy = 'Trend Following';
  List<String> _selectedSymbols = [];
  String _selectedTraditionalVolatilityFilter = 'All';
  String _selectedBinanceQuoteFilter = 'All';
  String _selectedBinanceCategoryFilter = 'All';
  String _binanceSymbolSearchQuery = '';
  bool _isCreating = false;
  bool _isLoadingData = true;
  bool _isLoadingExistingBot = false;
  String? _successMessage;
  String? _errorMessage;

  // Auto-Withdrawal Settings
  String _withdrawalMode = 'fixed'; // 'fixed' or 'intelligent' or 'milestone'
  double _targetProfit = 300; // For fixed mode
  double _minProfit = 50; // For intelligent mode
  double _maxProfit = 500; // For intelligent mode
  double _winRateMin = 60; // For intelligent mode
  bool _enableAutoWithdrawal = false;

  // Profit Protection Settings
  bool _enableProfitProtection = true;
  double _profitProtectionActivationPercent = 3;
  double _profitProtectionActivationMinProfit = 0.50;  // 🎯 Aggressive early activation (was 5)
  double _profitProtectionMinLockedProfit = 0.30;  // Lock 30% minimum (was 0)
  double _profitProtectionMarginTakeProfitPercent = 30;
  double _profitProtectionRetracePercent = 25;  // Exit on 25% retrace (was 12) - let trends play out
  bool _profitProtectionSwitchOnReversal = false;  // Don't reverse position on micro-reversals
  bool _profitProtectionAdaptiveByVolatility = true;
  bool _copyTradingEnabled = false;
  String _copyTradingSourceMode = 'auto_success';
  String? _copyTradingSourceBotId;
  String? _copyTradingResolvedSourceBotId;
  String? _copyTradingSourceFeedback;
  List<Map<String, dynamic>> _copyTradingSources = [];
  bool _isLoadingCopyTradingSources = false;

  // Milestone Auto-Withdrawal Settings
  double _milestoneOneProfitPercent = 20;
  double _milestoneOneWithdrawPercent = 20;
  double _milestoneTwoProfitPercent = 50;
  double _milestoneTwoWithdrawPercent = 50;

  // Currency & Settings
  String _currencyChoice = 'USD';

  // Small Account Presets
  String? _selectedPreset;
  List<Map<String, dynamic>> _testedBotTemplates = [];
  bool _isLoadingTestedBotTemplates = false;

  static const Map<String, Map<String, dynamic>> _smallAccountPresets = {
    'crypto': {
      'name': 'Crypto',
      'icon': '₿',
      'description': 'DCA into BTC/ETH with swing trend entries.',
      'recommendedMinUsd': 10.0,
      'recommendedMaxUsd': 1000.0,
      'accountLabel': 'crypto accounts',
      'intelligentScanner': true,
      'symbols': ['BTCUSD', 'ETHUSD'],
      'strategy': 'Swing Trend DCA',
      'managementProfile': 'small_account',
      'riskPercent': 5.0,
      'maxDailyLoss': 50.0,
      'maxOpenTrades': 5,
      'maxDrawdownPercent': 20.0,
      'allowedVolatility': ['Very Low', 'Low', 'Medium'],
      'tips': [
        'DCA weekly: buy fixed amount regardless of price',
        'Only spot or max 2-5x leverage',
        'Stick to BTC + ETH (majors only)',
        'Expect 5-8% monthly net on a good run',
      ],
    },
    'forex': {
      'name': 'Forex',
      'icon': '💱',
      'description':
          'Swing trend following on major pairs with micro lots.',
      'recommendedMinUsd': 10.0,
      'recommendedMaxUsd': 1000.0,
      'accountLabel': 'forex accounts',
      'intelligentScanner': true,
      'symbols': ['EURUSD'],
      'strategy': 'Swing Trend DCA',
      'managementProfile': 'small_account',
      'riskPercent': 5.0,
      'maxDailyLoss': 50.0,
      'maxOpenTrades': 5,
      'maxDrawdownPercent': 20.0,
      'allowedVolatility': ['Very Low', 'Low', 'Medium'],
      'tips': [
        'Use cent/micro account (0.01 lots)',
        'Only EUR/USD and GBP/USD (tightest spreads)',
        'Trade during London/NY overlap (15:00-19:00 SAST)',
        'Target 1:2 or 1:3 risk-reward minimum',
      ],
    },
    'stocks': {
      'name': 'Stocks',
      'icon': '📈',
      'description': 'Swing pullback entries on blue-chip stocks/ETFs.',
      'recommendedMinUsd': 50.0,
      'recommendedMaxUsd': 1000.0,
      'accountLabel': 'stock accounts',
      'intelligentScanner': true,
      'symbols': ['NVDA', 'AAPL', 'MSFT'],
      'strategy': 'Swing Trend DCA',
      'managementProfile': 'small_account',
      'riskPercent': 5.0,
      'maxDailyLoss': 20.0,
      'maxOpenTrades': 2,
      'maxDrawdownPercent': 15.0,
      'allowedVolatility': ['Very Low', 'Low', 'Medium'],
      'tips': [
        'Use fractional shares or CFDs for small sizing',
        'Focus on mega-cap tech (NVDA, AAPL, MSFT)',
        'Check earnings calendar — avoid holding through earnings',
        'Trail stop with 50 SMA on daily chart',
      ],
    },
    'commodities': {
      'name': 'Gold',
      'icon': '🥇',
      'description': 'Swing trend following on gold (XAU/USD).',
      'recommendedMinUsd': 100.0,
      'recommendedMaxUsd': 1000.0,
      'accountLabel': 'commodity accounts',
      'intelligentScanner': true,
      'symbols': ['XAUUSD'],
      'strategy': 'Swing Trend DCA',
      'managementProfile': 'small_account',
      'riskPercent': 5.0,
      'maxDailyLoss': 50.0,
      'maxOpenTrades': 3,
      'maxDrawdownPercent': 20.0,
      'allowedVolatility': ['Very Low', 'Low', 'Medium'],
      'tips': [
        'Gold is volatile — use wider stops (1.5-2x ATR)',
        'Only trade with the daily trend',
        'Avoid trading on FOMC / NFP days',
        'CFDs keep position sizes minimal',
      ],
    },
    'mixed': {
      'name': 'Mixed',
      'icon': '🎯',
      'description':
          'Diversified swing trading across forex, crypto, and gold.',
      'recommendedMinUsd': 100.0,
      'recommendedMaxUsd': 1000.0,
      'accountLabel': 'mixed-market accounts',
      'intelligentScanner': true,
      'symbols': ['EURUSD', 'BTCUSD', 'XAUUSD'],
      'strategy': 'Swing Trend DCA',
      'managementProfile': 'small_account',
      'riskPercent': 5.0,
      'maxDailyLoss': 50.0,
      'maxOpenTrades': 5,
      'maxDrawdownPercent': 20.0,
      'allowedVolatility': ['Very Low', 'Low', 'Medium'],
      'tips': [
        'Max 3 assets — keeps risk manageable',
        'Gold hedges crypto drops',
        'Forex provides steady base returns',
        'Rebalance monthly based on performance',
      ],
    },
    'optimised': {
      'name': 'Optimised',
      'icon': '⚡',
      'description':
          'Top pairs from live trade history — Silver, AUD/USD, USD/CHF, GBP/JPY during London/NY overlap.',
      'recommendedMinUsd': 50.0,
      'recommendedMaxUsd': 5000.0,
      'accountLabel': 'Exness MT5 accounts',
      'intelligentScanner': true,
      'symbols': ['XAGUSDm', 'AUDUSDm', 'USDCHFm', 'GBPJPYm'],
      'strategy': 'Trend Following',
      'managementProfile': 'small_account',
      'riskPercent': 3.0,
      'maxDailyLoss': 30.0,
      'maxOpenTrades': 2,
      'maxDrawdownPercent': 12.0,
      'signalThreshold': 65,
      'allowedVolatility': ['Low', 'Medium'],
      'tips': [
        'Only trade 08:00–15:00 UTC (London/NY overlap)',
        'XAG/USD is priority — wider stops (200 pts) needed',
        'Max 2 open positions at any time',
        'Signal strength ≥ 65 — filters out weak entries',
        'TP:SL ratio minimum 1.75:1',
      ],
    },
    'weekend_crypto': {
      'name': 'Weekend',
      'icon': '🔥',
      'description':
          'BTC & ETH swing trades — runs 24/7 including weekends when forex is closed.',
      'recommendedMinUsd': 50.0,
      'recommendedMaxUsd': 10000.0,
      'accountLabel': 'Exness crypto accounts',
      'intelligentScanner': false,
      'symbols': ['BTCUSDT', 'ETHUSDT'],
      'strategy': 'Trend Following',
      'managementProfile': 'small_account',
      'riskPercent': 5.0,
      'maxDailyLoss': 100.0,
      'maxOpenTrades': 5,
      'maxDrawdownPercent': 25.0,
      'signalThreshold': 15,
      'allowedVolatility': ['Medium', 'High'],
      'tips': [
        'BTC target: R200–R1000+ per trade at 0.10 lot',
        'ETH target: R200–R700+ per trade at 0.10 lot',
        'Max 5 open positions (crypto is volatile)',
        'Signal ≥ 15 before entering — allows more entries',
        'Bot auto-sizes to 0.10 lot for meaningful profit',
      ],
    },
  };

  void _applySmallAccountPreset(String presetKey) {
    final preset = _smallAccountPresets[presetKey];
    if (preset == null) return;

    setState(() {
      _selectedPreset = presetKey;
      _selectedStrategy = preset['strategy'] as String;
      _managementProfile = preset['managementProfile'] as String;
      _intelligentScanner =
          preset['intelligentScanner'] as bool? ?? _intelligentScanner;
      _riskPercent = (preset['riskPercent'] as num).toDouble();
      _maxOpenTrades = preset['maxOpenTrades'] as int;
      _maxDrawdownPercent = (preset['maxDrawdownPercent'] as num).toDouble();
      _manualSignalThreshold = preset.containsKey('signalThreshold')
          ? preset['signalThreshold'] as int
          : null;
      _allowedVolatility = List<String>.from(
        preset['allowedVolatility'] as List,
      );

      // Apply symbols:
      // - Binance broker: only apply symbols for crypto presets (use USDT format)
      // - MT5/Exness: apply preset symbols as-is
      if (_isBinanceBroker) {
        if (presetKey == 'weekend_crypto' || presetKey == 'crypto') {
          _selectedSymbols = ['BTCUSDT', 'ETHUSDT'];
        }
        // Other presets don\'t apply symbols on Binance — use Quick Actions panel
      } else {
        _selectedSymbols = List<String>.from(preset['symbols'] as List);
      }
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${preset['name']} preset applied!'),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // Broker integration
  late BrokerCredentialsService _brokerService;
  late CommissionService _commissionService;

  Map<String, dynamic> commodityMarketData = {};
  List<Map<String, String>> tradingSymbols = []; // Will be populated from API
  Set<String> _blacklistedSymbols = {}; // Symbols blacklisted by performance guard in this bot

  String get _activeBrokerName =>
      _brokerService.activeCredential?.broker.toLowerCase().trim() ?? '';

  bool get _isBinanceBroker => _activeBrokerName == 'binance';

  bool get _isExnessBroker =>
      const {'exness', 'xm', 'xm global'}.contains(_activeBrokerName);

  String get _symbolSectionTitle =>
      _isBinanceBroker ? 'Select Binance Pairs' : 'Select Trading Symbols';

  String get _symbolSelectionError => _isBinanceBroker
      ? 'Please select at least one Binance pair'
      : 'Please select at least one trading symbol';

  List<Map<String, dynamic>> get _rankedBinancePairs {
    final sourceSymbols = (_isBinanceBroker && tradingSymbols.isNotEmpty)
        ? tradingSymbols
        : _binanceSymbols;
    final ranked = sourceSymbols.map((item) {
      final symbol = item['symbol']!;
      final insight = _binanceAnalyticsForSymbol(symbol);
      final edge = (insight['edgePct'] as num?)?.toDouble() ?? 0.0;
      final winRate = (insight['winRate'] as num?)?.toDouble() ?? 0.0;
      final liquidity = (insight['liquidityScore'] as num?)?.toDouble() ?? 50.0;
      final score = (edge * 0.45) + (winRate * 0.35) + ((liquidity / 100) * 20);

      return {
        'symbol': symbol,
        'name': item['name'],
        'category': item['category'],
        'edgePct': edge,
        'winRate': winRate,
        'liquidityScore': liquidity,
        'risk': insight['risk'] ?? 'Medium',
        'analysis': insight['analysis'] ?? 'General trend',
        'score': score,
      };
    }).toList();

    ranked.sort(
      (a, b) => (b['score'] as double).compareTo(a['score'] as double),
    );
    return ranked;
  }

  void _applyBinancePreset(String preset) {
    if (!_isBinanceBroker) {
      return;
    }

    final ranked = _rankedBinancePairs;
    final sourceSymbols = (_isBinanceBroker && tradingSymbols.isNotEmpty)
      ? tradingSymbols
      : _binanceSymbols;
    List<String> symbols;

    switch (preset) {
      case 'top_edge':
        symbols = ranked
            .take(5)
            .map((item) => item['symbol'] as String)
            .toList();
        break;
      case 'high_liquidity':
        symbols = ranked
            .where((item) => (item['liquidityScore'] as double) >= 85)
            .take(6)
            .map((item) => item['symbol'] as String)
            .toList();
        break;
      case 'balanced':
        symbols = ranked
            .where((item) => item['risk'] == 'Low' || item['risk'] == 'Medium')
            .take(6)
            .map((item) => item['symbol'] as String)
            .toList();
        break;
      case 'weekend_btc_eth':
        symbols = ['BTCUSDT', 'ETHUSDT'];
        break;
      case 'defi':
        symbols = sourceSymbols
            .where(
              (item) => (item['category'] ?? '').toString().toLowerCase().contains('defi'),
            )
            .take(6)
            .map((item) => item['symbol']!)
            .toList();
        break;
      case 'clear':
        symbols = [];
        break;
      default:
        symbols = _selectedSymbols;
    }

    setState(() {
      _selectedSymbols = symbols;
    });
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

  String _normalizeSymbolBase(String symbol) {
    var normalized = symbol
        .trim()
        .toUpperCase()
        .replaceAll('/', '')
        .replaceAll('_', '');
    if (normalized.endsWith('M') && normalized.length > 1) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    return normalized;
  }

  static final Set<String> _primaryCryptoSymbols = {
    'BTCUSD',
    'ETHUSD',
    for (final item in _binanceSymbols) item['symbol']!,
  };

  static const Set<String> _safeCryptoStrategies = {
    'Trend Following',
    'Swing Trend DCA',
  };

  Set<String> get _selectedBaseSymbols => _selectedSymbols
      .map(_normalizeSymbolBase)
      .where((symbol) => symbol.isNotEmpty)
      .toSet();

  bool get _isCryptoOnlySelection {
    if (_isBinanceBroker) {
      return _selectedSymbols.isNotEmpty;
    }

    final symbols = _selectedBaseSymbols;
    return symbols.isNotEmpty &&
        symbols.every((symbol) => _primaryCryptoSymbols.contains(symbol));
  }

  List<String> get _availableStrategies {
    if (_isCryptoOnlySelection) {
      return strategies
          .where((strategy) => _safeCryptoStrategies.contains(strategy))
          .toList();
    }
    return strategies;
  }

    int get _cryptoOnlyAutoThreshold => 15;

    String _binanceQuoteAsset(String symbol) {
      final normalized = _normalizeSymbolBase(symbol);
      for (final quote in const ['USDT', 'BTC', 'ETH', 'BNB']) {
        if (normalized.length > quote.length && normalized.endsWith(quote)) {
          return quote;
        }
      }
      return '';
    }

    String _binanceBaseAsset(String symbol) {
      final normalized = _normalizeSymbolBase(symbol);
      final quote = _binanceQuoteAsset(normalized);
      if (quote.isEmpty) {
        return normalized;
      }
      return normalized.substring(0, normalized.length - quote.length);
    }

    String _binanceAnalyticsKey(String symbol) {
      final normalized = _normalizeSymbolBase(symbol);
      if (_binancePairAnalytics.containsKey(normalized)) {
        return normalized;
      }

      final baseAsset = _binanceBaseAsset(normalized);
      final fallback = '${baseAsset}USDT';
      return _binancePairAnalytics.containsKey(fallback) ? fallback : normalized;
    }

    Map<String, dynamic> _binanceAnalyticsForSymbol(String symbol) {
      return _binancePairAnalytics[_binanceAnalyticsKey(symbol)] ?? const {};
    }

    List<String> get _binanceCategoryFilters {
        final sourceSymbols = (_isBinanceBroker && tradingSymbols.isNotEmpty)
            ? tradingSymbols
            : _binanceSymbols;
        final categories = sourceSymbols
          .map((item) => item['category'] ?? 'General')
          .toSet()
          .toList()
        ..sort();
      return ['All', ...categories];
    }

    List<String> get _binanceQuoteFilters {
      final sourceSymbols = (_isBinanceBroker && tradingSymbols.isNotEmpty)
          ? tradingSymbols
          : _binanceSymbols;
      final quotes = sourceSymbols
          .map((item) => _binanceQuoteAsset(item['symbol'] ?? ''))
          .where((quote) => quote.isNotEmpty)
          .toSet()
          .toList()
        ..sort();
      return ['All', ...quotes];
    }

    bool _matchesBinanceFilters(Map<String, String> symbol) {
      final symbolCode = symbol['symbol'] ?? '';
      final symbolName = symbol['name'] ?? symbolCode;
      final category = symbol['category'] ?? 'General';
      final quote = _binanceQuoteAsset(symbolCode);
      final query = _binanceSymbolSearchQuery.trim().toLowerCase();

      if (_selectedBinanceQuoteFilter != 'All' && quote != _selectedBinanceQuoteFilter) {
        return false;
      }
      if (_selectedBinanceCategoryFilter != 'All' && category != _selectedBinanceCategoryFilter) {
        return false;
      }
      if (query.isNotEmpty) {
        final haystack = '$symbolCode $symbolName $category ${_binanceBaseAsset(symbolCode)} ${quote.isEmpty ? '' : quote}'
            .toLowerCase();
        if (!haystack.contains(query)) {
          return false;
        }
      }
      return true;
    }

List<int> get _availableSignalThresholds {
     if (_isCryptoOnlySelection) {
       return const [1, 5, 10, 15, 20, 30];
     }
     return const [10, 20, 30, 40, 50, 60];
   }

  void _applyCryptoSelectionSafetyDefaults() {
    if (!_isCryptoOnlySelection) {
      return;
    }

    if (!_safeCryptoStrategies.contains(_selectedStrategy)) {
      _selectedStrategy = 'Swing Trend DCA';
    }

    if (_manualSignalThreshold != null && _manualSignalThreshold! < 5) {
      _manualSignalThreshold = 5;
    }
  }

  /// Auto-selects the top recommended symbols for the active broker on new-bot
  /// creation, so users start with a sensible safe default instead of nothing.
  /// Only runs when [_selectedSymbols] is empty (i.e. no preset has been applied).
  void _autoSelectDefaultSymbols() {
    if (_isEditMode || _selectedSymbols.isNotEmpty) return;

    final available = tradingSymbols
        .map((item) => item['symbol'])
        .whereType<String>()
        .toList();
    if (available.isEmpty) return;

    if (_isBinanceBroker) {
      // Binance: top 5 by edge/win-rate score, prefer Low-Medium risk
      final ranked = _rankedBinancePairs;
      final preferred = ranked
          .where((p) => p['risk'] == 'Low' || p['risk'] == 'Medium')
          .take(5)
          .map((p) => p['symbol'] as String)
          .toList();
      _selectedSymbols = preferred.isNotEmpty
          ? preferred
          : ranked.take(5).map((p) => p['symbol'] as String).toList();
    } else {
      // Exness / MT5: rank available symbols by live signal strength from
      // commodityMarketData, falling back to a static preferred order.
      // Exclude high-volatility single-asset crypto (BTCUSD, ETHUSD) from
      // the default selection so beginners start with forex/gold.
      const excludeByDefault = {'BTCUSD', 'ETHUSD', 'BTCUSDM', 'ETHUSDM'};
      const staticTopPicks = [
        'GBPUSD', 'EURUSD', 'USDJPY', 'XAUUSD',
        'AUDUSD', 'USDCAD', 'USDCHF', 'GBPJPY',
      ];

      // Score each available symbol by signal strength
      final scored = <Map<String, dynamic>>[];
      for (final sym in available) {
        final normalizedSym = _normalizeSymbolBase(sym);
        if (excludeByDefault.contains(normalizedSym)) continue;
        final marketData = _normalizeMarketDataEntry(
          commodityMarketData[sym] ??
              commodityMarketData[normalizedSym],
        );
        final signal = _marketSignalStrength(marketData);
        // Static rank from preferred list gives a tiebreaker bonus
        final staticRank = staticTopPicks.indexWhere(
          (pick) => _normalizeSymbolBase(pick) == normalizedSym,
        );
        final bonus = staticRank >= 0 ? (8 - staticRank) * 2.0 : 0.0;
        scored.add({'symbol': sym, 'score': signal + bonus});
      }

      scored.sort(
        (a, b) => (b['score'] as double).compareTo(a['score'] as double),
      );

      if (scored.isNotEmpty) {
        _selectedSymbols = scored
            .take(4)
            .map((e) => e['symbol'] as String)
            .toList();
      } else {
        // No market data at all — fall back to static preferred list
        final normalizedToAvailable = <String, String>{
          for (final s in available) _normalizeSymbolBase(s): s,
        };
        final autoSelected = <String>[];
        for (final pick in staticTopPicks) {
          final mapped = normalizedToAvailable[_normalizeSymbolBase(pick)];
          if (mapped != null) autoSelected.add(mapped);
          if (autoSelected.length >= 4) break;
        }
        _selectedSymbols = autoSelected;
      }
    }
  }

  List<String> _remapSelectedSymbolsToAvailable(List<String> availableSymbols) {
    if (_selectedSymbols.isEmpty || availableSymbols.isEmpty) {
      return List<String>.from(_selectedSymbols);
    }

    final normalizedToAvailable = <String, String>{};
    for (final availableSymbol in availableSymbols) {
      normalizedToAvailable.putIfAbsent(
        _normalizeSymbolBase(availableSymbol),
        () => availableSymbol,
      );
    }

    final remapped = <String>[];
    for (final selectedSymbol in _selectedSymbols) {
      final normalized = _normalizeSymbolBase(selectedSymbol);
      final mapped = normalizedToAvailable[normalized];
      if (mapped != null && !remapped.contains(mapped)) {
        remapped.add(mapped);
      }
    }
    return remapped;
  }

  bool _isSymbolSelected(String symbolCode) {
    final normalized = _normalizeSymbolBase(symbolCode);
    return _selectedSymbols.any(
      (symbol) => _normalizeSymbolBase(symbol) == normalized,
    );
  }

  String _traditionalVolatilityBucket(String symbol) {
    final normalized = _normalizeSymbolBase(symbol);

    final binanceRisk = _binanceAnalyticsForSymbol(normalized)['risk']?.toString();
    if (binanceRisk != null && binanceRisk.isNotEmpty) {
      switch (binanceRisk.toLowerCase()) {
        case 'low':
          return 'Stable';
        case 'high':
          return 'High Volatility';
        default:
          return 'Moderate';
      }
    }

    const highVolatility = {
      'BTCUSD',
      'ETHUSD',
      'USOIL',
      'UKOIL',
      'XAUUSD',
      'USTEC',
      'US30',
      'TSLA',
      'NVDA',
      'META',
      'AMD',
      'GBPJPY',
      'EURJPY',
      'GOLD',
      'SILVER',
      'USOILSPOT',
      'UKOILSPOT',
      'NAS100',
      'GER30',
      'UK100',
      'JPN225',
      'SPX500',
      'US2000',
    };

    const stableSymbols = {
      'EURUSD',
      'USDCHF',
      'USDCAD',
      'EURGBP',
      'USDJPY',
      'JPM',
      'BAC',
      'WFC',
    };

    if (highVolatility.contains(normalized)) {
      return 'High Volatility';
    }
    if (stableSymbols.contains(normalized)) {
      return 'Stable';
    }
    return 'Moderate';
  }

  Color _traditionalVolatilityColor(String bucket) {
    switch (bucket) {
      case 'High Volatility':
        return Colors.deepOrangeAccent;
      case 'Stable':
        return Colors.lightBlueAccent;
      default:
        return Colors.amberAccent;
    }
  }

  int _traditionalVolatilityRank(String bucket) {
    switch (bucket) {
      case 'Stable':
        return 0;
      case 'Moderate':
        return 1;
      case 'High Volatility':
        return 2;
      default:
        return 3;
    }
  }

  bool _isTraditionalForexSymbol(String symbol) {
    final normalized = _normalizeSymbolBase(symbol);
    const forexCurrencies = {
      'AUD',
      'CAD',
      'CHF',
      'EUR',
      'GBP',
      'JPY',
      'NZD',
      'USD',
      'ZAR',
    };
    return normalized.length == 6 &&
        forexCurrencies.contains(normalized.substring(0, 3)) &&
        forexCurrencies.contains(normalized.substring(3));
  }

  int _traditionalRecommendedRank(String symbol) {
    final normalized = _normalizeSymbolBase(symbol);
    final index = _traditionalRecommendedSymbolOrder.indexOf(normalized);
    return index >= 0 ? index : _traditionalRecommendedSymbolOrder.length + 20;
  }

  String _traditionalGroupTitle(Map<String, String> symbol) {
    final symbolCode = symbol['symbol'] ?? '';
    final normalized = _normalizeSymbolBase(symbolCode);
    final category = (symbol['category'] ?? '').toLowerCase();
    final recommendationRank = _traditionalRecommendedRank(symbolCode);

    if (recommendationRank < 7) {
      return 'Recommended Starters';
    }
    if (_isTraditionalForexSymbol(normalized)) {
      final quote = normalized.substring(3);
      if (quote == 'USD' || normalized.startsWith('USD')) {
        return 'Forex Majors';
      }
      return 'Forex Crosses';
    }
    if (category.contains('metal') ||
        category.contains('energy') ||
        category.contains('commod')) {
      return 'Metals & Commodities';
    }
    if (category.contains('indice') || category.contains('index')) {
      return 'Indices';
    }
    if (category.contains('crypto')) {
      return 'Crypto';
    }
    if (category.contains('treasury')) {
      return 'Rates & Treasury';
    }
    if (category.contains('stock')) {
      return 'Stocks';
    }
    return 'Other Markets';
  }

  int _traditionalGroupRank(Map<String, String> symbol) {
    switch (_traditionalGroupTitle(symbol)) {
      case 'Recommended Starters':
        return 0;
      case 'Forex Majors':
        return 1;
      case 'Forex Crosses':
        return 2;
      case 'Metals & Commodities':
        return 3;
      case 'Indices':
        return 4;
      case 'Crypto':
        return 5;
      case 'Rates & Treasury':
        return 6;
      case 'Stocks':
        return 7;
      default:
        return 8;
    }
  }

  List<Map<String, String>> get _filteredTradingSymbols {
    final visibleSymbols = List<Map<String, String>>.from(tradingSymbols)
        .where((symbol) {
      final code = (symbol['symbol'] ?? '').toUpperCase();
      return !_blacklistedSymbols.contains(code);
    }).toList();

    if (_isBinanceBroker) {
      visibleSymbols.sort((left, right) {
        final leftAnalytics = _binanceAnalyticsForSymbol(left['symbol'] ?? '');
        final rightAnalytics = _binanceAnalyticsForSymbol(right['symbol'] ?? '');
        final leftScore = ((_safeToDouble(leftAnalytics['edgePct']) * 0.45) +
                (_safeToDouble(leftAnalytics['winRate']) * 0.35) +
                ((_safeToDouble(leftAnalytics['liquidityScore']) / 100) * 20))
            .toDouble();
        final rightScore = ((_safeToDouble(rightAnalytics['edgePct']) * 0.45) +
                (_safeToDouble(rightAnalytics['winRate']) * 0.35) +
                ((_safeToDouble(rightAnalytics['liquidityScore']) / 100) * 20))
            .toDouble();
        final scoreComparison = rightScore.compareTo(leftScore);
        if (scoreComparison != 0) {
          return scoreComparison;
        }

        final leftCategory = left['category'] ?? '';
        final rightCategory = right['category'] ?? '';
        final categoryComparison = leftCategory.compareTo(rightCategory);
        if (categoryComparison != 0) {
          return categoryComparison;
        }

        final leftQuote = _binanceQuoteAsset(left['symbol'] ?? '');
        final rightQuote = _binanceQuoteAsset(right['symbol'] ?? '');
        final quoteComparison = leftQuote.compareTo(rightQuote);
        if (quoteComparison != 0) {
          return quoteComparison;
        }

        final leftName = left['name'] ?? left['symbol'] ?? '';
        final rightName = right['name'] ?? right['symbol'] ?? '';
        return leftName.compareTo(rightName);
      });

      return visibleSymbols.where(_matchesBinanceFilters).toList();
    }

    visibleSymbols.sort((left, right) {
      final leftGroupRank = _traditionalGroupRank(left);
      final rightGroupRank = _traditionalGroupRank(right);
      final groupComparison = leftGroupRank.compareTo(rightGroupRank);
      if (groupComparison != 0) {
        return groupComparison;
      }

      final recommendationComparison = _traditionalRecommendedRank(
        left['symbol'] ?? '',
      ).compareTo(_traditionalRecommendedRank(right['symbol'] ?? ''));
      if (recommendationComparison != 0) {
        return recommendationComparison;
      }

      final leftBucket = _traditionalVolatilityBucket(left['symbol']!);
      final rightBucket = _traditionalVolatilityBucket(right['symbol']!);
      final bucketComparison = _traditionalVolatilityRank(
        leftBucket,
      ).compareTo(_traditionalVolatilityRank(rightBucket));
      if (bucketComparison != 0) {
        return bucketComparison;
      }

      final leftCategory = left['category'] ?? '';
      final rightCategory = right['category'] ?? '';
      final categoryComparison = leftCategory.compareTo(rightCategory);
      if (categoryComparison != 0) {
        return categoryComparison;
      }

      final leftName = left['name'] ?? left['symbol'] ?? '';
      final rightName = right['name'] ?? right['symbol'] ?? '';
      return leftName.compareTo(rightName);
    });

    if (_selectedTraditionalVolatilityFilter == 'All') {
      return visibleSymbols;
    }

    return visibleSymbols.where((symbol) {
      final symbolCode = symbol['symbol'];
      if (symbolCode == null) {
        return false;
      }
      return _traditionalVolatilityBucket(symbolCode) ==
          _selectedTraditionalVolatilityFilter;
    }).toList();
  }

  int get _hiddenSelectedSymbolCount {
    if (_isBinanceBroker) {
      final visibleBySymbol = {
        for (final symbol in tradingSymbols) (symbol['symbol'] ?? ''): symbol,
      };
      return _selectedSymbols.where((symbolCode) {
        final entry = visibleBySymbol[symbolCode];
        if (entry == null) {
          return true;
        }
        return !_matchesBinanceFilters(entry);
      }).length;
    }

    if (_selectedTraditionalVolatilityFilter == 'All') {
      return 0;
    }

    return _selectedSymbols.where((symbolCode) {
      return _traditionalVolatilityBucket(symbolCode) !=
          _selectedTraditionalVolatilityFilter;
    }).length;
  }

  double _usdToAccountCurrencyRate(String currencyCode) {
    switch (currencyCode.toUpperCase()) {
      case 'ZAR':
        return 18.5;
      case 'GBP':
        return 0.80;
      case 'EUR':
        return 0.92;
      default:
        return 1.0;
    }
  }

  double _symbolMinimumUsd(String symbol) {
    final normalized = symbol.toUpperCase();
    if (normalized.contains('BTC') || normalized.contains('ETH')) {
      return 15.0;
    }
    if (normalized.contains('XAU') ||
        normalized.contains('XAG') ||
        normalized.contains('OIL')) {
      return 10.0;
    }
    if (normalized.contains('US30') ||
        normalized.contains('US500') ||
        normalized.contains('USTEC')) {
      return 12.0;
    }
    if ({
      'NVDA',
      'AAPL',
      'MSFT',
      'META',
      'GOOGL',
      'TSLA',
      'AMD',
    }.contains(normalized)) {
      return 20.0;
    }
    return 5.0;
  }

  Map<String, dynamic>? _fixedTradeAmountWarningData(BuildContext context) {
    final rawAmount = double.tryParse(_investmentAmountController.text.trim());
    if (rawAmount == null || rawAmount <= 0 || _selectedSymbols.isEmpty) {
      return null;
    }

    final currencyCode = _activeAccountCurrencyCode(context);
    final rate = _usdToAccountCurrencyRate(currencyCode);
    final symbolMinimums = <Map<String, dynamic>>[];
    for (final symbol in _selectedSymbols) {
      final usdMinimum = _symbolMinimumUsd(symbol);
      symbolMinimums.add({'symbol': symbol, 'minimum': usdMinimum * rate});
    }

    symbolMinimums.sort(
      (a, b) => (b['minimum'] as double).compareTo(a['minimum'] as double),
    );
    final highest = symbolMinimums.first;
    final estimatedMinimum = highest['minimum'] as double;

    if (rawAmount + 1e-9 >= estimatedMinimum) {
      return null;
    }

    final limitedSymbols = symbolMinimums
        .take(3)
        .map((item) => item['symbol'])
        .join(', ');
    return {
      'entered': rawAmount,
      'currency': currencyCode,
      'minimum': estimatedMinimum,
      'symbols': limitedSymbols,
      'primarySymbol': highest['symbol'],
    };
  }

  Future<bool> _confirmLowFixedTradeAmount(
    BuildContext context,
    Map<String, dynamic> warning,
  ) async {
    final proceed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Low Trade Amount'),
        content: Text(
          'You entered ${warning['entered'].toStringAsFixed(2)} ${warning['currency']} per trade, '
          'but ${warning['primarySymbol']} usually needs about '
          '${warning['minimum'].toStringAsFixed(2)} ${warning['currency']} or more to clear minimum lot sizing.\n\n'
          'The bot may round up to the broker minimum or place smaller-than-expected exposure. Continue anyway?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Back'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Continue'),
          ),
        ],
      ),
    );

    return proceed == true;
  }

  String _activeAccountCurrencyCode(BuildContext context) {
    final credentialCurrency = _brokerService.activeCredential?.accountCurrency;
    if (credentialCurrency != null && credentialCurrency.trim().isNotEmpty) {
      return credentialCurrency.trim().toUpperCase();
    }
    if (_currencyChoice.trim().isNotEmpty) {
      return _currencyChoice.trim().toUpperCase();
    }
    return _currencyCode(context.read<CurrencyProvider>().currency);
  }

  bool get _hasLinkedAccountCurrency {
    final credentialCurrency = _brokerService.activeCredential?.accountCurrency;
    return credentialCurrency != null && credentialCurrency.trim().isNotEmpty;
  }

  String _currencyPrefixForCode(String currencyCode) {
    switch (currencyCode.toUpperCase()) {
      case 'ZAR':
        return 'R ';
      case 'GBP':
        return '£ ';
      case 'EUR':
        return '€ ';
      default:
        return r'$ ';
    }
  }

  String _formatCompactCurrency(double amount, String currencyCode) {
    return '${_currencyPrefixForCode(currencyCode)}${amount.toStringAsFixed(2)}';
  }

  String _formatPresetTradeAmount(double amount, String currencyCode) {
    final prefix = _currencyPrefixForCode(currencyCode);
    final wholeAmount = amount == amount.roundToDouble();
    return '$prefix${wholeAmount ? amount.toStringAsFixed(0) : amount.toStringAsFixed(2)}';
  }

  String _currencyUnitName(String currencyCode) {
    switch (currencyCode.toUpperCase()) {
      case 'ZAR':
        return 'rands';
      case 'GBP':
        return 'pounds';
      case 'EUR':
        return 'euros';
      default:
        return 'dollars';
    }
  }

  String _formatPresetRange(
    double minimumUsd,
    double maximumUsd,
    String currencyCode,
  ) {
    final rate = _usdToAccountCurrencyRate(currencyCode);
    final minimum = minimumUsd * rate;
    final maximum = maximumUsd * rate;
    return '${_formatPresetTradeAmount(minimum, currencyCode)} - ${_formatPresetTradeAmount(maximum, currencyCode)}';
  }

  String _presetRecommendedRangeText(String presetKey, String currencyCode) {
    final preset = _smallAccountPresets[presetKey];
    if (preset == null) {
      return '';
    }
    final minimumUsd = (preset['recommendedMinUsd'] as num?)?.toDouble();
    final maximumUsd = (preset['recommendedMaxUsd'] as num?)?.toDouble();
    if (minimumUsd == null || maximumUsd == null) {
      return '';
    }
    final accountLabel = (preset['accountLabel'] as String?) ?? 'accounts';
    return 'Best for ${_formatPresetRange(minimumUsd, maximumUsd, currencyCode)} $accountLabel.';
  }

  void _applyTradeAmountPreset(double amount) {
    _investmentAmountController.text = amount == amount.roundToDouble()
        ? amount.toStringAsFixed(0)
        : amount.toStringAsFixed(2);
    _investmentAmountController.selection = TextSelection.fromPosition(
      TextPosition(offset: _investmentAmountController.text.length),
    );
    setState(() {});
  }

  String _credentialStatusText(BrokerCredential credential) {
    if (credential.isHealthy) {
      return 'Cache ${_formatCompactCurrency(credential.cachedBalance, credential.accountCurrency)}';
    }
    return 'No cached balance';
  }

  Color _credentialModeColor(BrokerCredential credential) {
    return credential.isLive ? Colors.red : Colors.green;
  }

  String _credentialModeLabel(BrokerCredential credential) {
    return credential.isLive ? 'LIVE' : 'DEMO';
  }

  Widget _binanceQuickActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color? color,
  }) {
    final chipColor = color ?? const Color(0xFFF0B90B);
    return ActionChip(
      avatar: Icon(icon, size: 16, color: chipColor),
      label: Text(label),
      backgroundColor: chipColor.withOpacity(0.15),
      side: BorderSide(color: chipColor.withOpacity(0.4)),
      onPressed: onTap,
    );
  }

  Widget _buildBinanceSetupInsights() {
    final topPairs = _rankedBinancePairs.take(3).toList();
    final selectedInsights = _selectedSymbols
        .map((s) => _binancePairAnalytics[s])
        .where((v) => v != null)
        .cast<Map<String, dynamic>>()
        .toList();

    final avgEdge = selectedInsights.isEmpty
        ? 0.0
        : selectedInsights
                  .map((i) => (i['edgePct'] as num?)?.toDouble() ?? 0.0)
                  .reduce((a, b) => a + b) /
              selectedInsights.length;
    final avgWinRate = selectedInsights.isEmpty
        ? 0.0
        : selectedInsights
                  .map((i) => (i['winRate'] as num?)?.toDouble() ?? 0.0)
                  .reduce((a, b) => a + b) /
              selectedInsights.length;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF0B90B).withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFF0B90B).withOpacity(0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Binance Quick Actions',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _binanceQuickActionButton(
                icon: Icons.bolt,
                label: 'Top Edge',
                onTap: () => _applyBinancePreset('top_edge'),
              ),
              _binanceQuickActionButton(
                icon: Icons.water_drop,
                label: 'High Liquidity',
                onTap: () => _applyBinancePreset('high_liquidity'),
              ),
              _binanceQuickActionButton(
                icon: Icons.balance,
                label: 'Balanced 6',
                onTap: () => _applyBinancePreset('balanced'),
              ),
              _binanceQuickActionButton(
                icon: Icons.weekend,
                label: 'Weekend BTC+ETH',
                onTap: () => _applyBinancePreset('weekend_btc_eth'),
                color: Colors.deepOrange,
              ),
              _binanceQuickActionButton(
                icon: Icons.auto_graph,
                label: 'DeFi Aggressive',
                onTap: () => _applyBinancePreset('defi'),
                color: Colors.deepPurpleAccent,
              ),
              _binanceQuickActionButton(
                icon: Icons.clear,
                label: 'Clear',
                onTap: () => _applyBinancePreset('clear'),
                color: Colors.redAccent,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            selectedInsights.isEmpty
                ? 'Select pairs to see estimated performance profile.'
                : 'Selected basket est. edge ${avgEdge.toStringAsFixed(1)}% | est. win rate ${avgWinRate.toStringAsFixed(1)}%',
            style: TextStyle(color: Colors.grey[300], fontSize: 11),
          ),
          const SizedBox(height: 8),
          const Text(
            'Most Lucrative Pairs (Model Ranking)',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          ...topPairs.asMap().entries.map((entry) {
            final rank = entry.key + 1;
            final pair = entry.value;
            return Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                '$rank. ${pair['symbol']}  | Edge ${(pair['edgePct'] as double).toStringAsFixed(1)}% | Win ${(pair['winRate'] as double).toStringAsFixed(0)}% | ${pair['analysis']}',
                style: TextStyle(color: Colors.grey[200], fontSize: 11),
              ),
            );
          }),
        ],
      ),
    );
  }

  void _applyManagementProfile(String profile) {
    setState(() {
      _managementProfile = profile;
      if (_selectedPreset != null && profile != 'small_account') {
        _selectedPreset = null;
      }
if (profile == 'beginner') {
         if (_maxOpenTrades > 10) _maxOpenTrades = 10;
         if (_riskPercent > 5.0) _riskPercent = 5.0;
         if (_maxDrawdownPercent > 30.0) _maxDrawdownPercent = 30.0;
         _allowedVolatility = ['Very Low', 'Low', 'Medium'];
       } else if (profile == 'balanced') {
         if (_maxOpenTrades > 10) _maxOpenTrades = 10;
         if (_riskPercent > 5.0) _riskPercent = 5.0;
         if (_maxDrawdownPercent > 30.0) _maxDrawdownPercent = 30.0;
         _allowedVolatility = ['Low', 'Medium', 'High'];
       } else if (profile == 'fast_growth') {
         // Quick Profit: faster cadence, but with tighter downside controls.
         _maxOpenTrades = 10;
         _riskPercent = 5.0;
         _maxDrawdownPercent = 30.0;
         _allowedVolatility = ['Low', 'Medium', 'High'];
         _targetProfit = 20; // Lower target for quick compounding
         _minProfit = 5;
         _maxProfit = 50;
         _winRateMin = 58;
         _profitProtectionActivationPercent = 2;
         _profitProtectionActivationMinProfit = 0.50;  // 🎯 Aggressive (was 2)
          _profitProtectionRetracePercent = 25;  // Consistent with default profit protection
       } else if (profile == 'small_account') {
         _maxOpenTrades = 10;
         _riskPercent = 5.0;
        _maxDrawdownPercent = 15.0;
        _allowedVolatility = ['Very Low', 'Low', 'Medium'];
      } else {
        _allowedVolatility = ['Low', 'Medium'];
      }
    });
  }

  int _defaultSignalThresholdForProfile(String profile) {
    if (_isCryptoOnlySelection) {
      return _cryptoOnlyAutoThreshold;
    }

    final isFxcmBroker = _activeBrokerName == 'fxcm';

    switch (profile) {
      case 'small_account':
        return 30;
      case 'beginner':
        return isFxcmBroker ? 45 : 60;
      case 'balanced':
        return isFxcmBroker ? 50 : 45;
      case 'advanced':
        return 30;
      case 'fast_growth':
        return 30;
      default:
        return 45;
    }
  }

  int _recommendedSignalThreshold() {
    return _manualSignalThreshold ?? _defaultSignalThresholdForProfile(_managementProfile);
  }

  String _signalThresholdLabel() {
    if (_manualSignalThreshold == null) {
      return 'Auto (${_defaultSignalThresholdForProfile(_managementProfile)})';
    }
    return '${_manualSignalThreshold!}';
  }

  int _recommendedMaxPositionsPerSymbol() {
    switch (_managementProfile) {
      case 'beginner':
      case 'small_account':
        return 1;
      case 'advanced':
        return _maxOpenTrades >= 3 ? 2 : 1;
      case 'balanced':
        return _maxOpenTrades >= 2 ? 2 : 1;
      default:
        return 1;
    }
  }

  List<String> _recommendedAllowedVolatility() {
    switch (_managementProfile) {
      case 'beginner':
        return ['Very Low', 'Low'];
      case 'small_account':
        return ['Very Low', 'Low', 'Medium'];
      default:
        return ['Low', 'Medium'];
    }
  }

  Map<String, dynamic> _recommendedTradingCadence() {
    final strategy = _selectedStrategy.trim().toLowerCase();
    final profile = _managementProfile.trim().toLowerCase();

    if (strategy == 'scalping') {
      return {
        'mode': 'signal-driven',
        'tradingInterval': 30,
        'pollInterval': 2,
      };
    }

    if (strategy == 'momentum trading' || strategy == 'breakout trading') {
      if (profile == 'advanced' || profile == 'fast_growth') {
        return {
          'mode': 'signal-driven',
          'tradingInterval': 60,
          'pollInterval': 5,
        };
      }
      return {
        'mode': 'signal-driven',
        'tradingInterval': 90,
        'pollInterval': 8,
      };
    }

    if (strategy == 'swing trend dca') {
      return {
        'mode': 'signal-driven',
        'tradingInterval': 300,
        'pollInterval': 30,
      };
    }

    if (_intelligentScanner) {
      if (profile == 'advanced' || profile == 'fast_growth') {
        return {
          'mode': 'signal-driven',
          'tradingInterval': 60,
          'pollInterval': 5,
        };
      }
      return {
        'mode': 'signal-driven',
        'tradingInterval': 120,
        'pollInterval': 10,
      };
    }

    if (profile == 'advanced' || profile == 'fast_growth') {
      return {
        'mode': 'signal-driven',
        'tradingInterval': 60,
        'pollInterval': 5,
      };
    }

    if (profile == 'balanced') {
      return {
        'mode': 'signal-driven',
        'tradingInterval': 90,
        'pollInterval': 8,
      };
    }

    return {
      'mode': 'signal-driven',
      'tradingInterval': 120,
      'pollInterval': 12,
    };
  }

  String _recommendedTradingMode() {
    return _recommendedTradingCadence()['mode'] as String;
  }

  int _recommendedTradingInterval() {
    return _recommendedTradingCadence()['tradingInterval'] as int;
  }

  int _recommendedPollInterval() {
    return _recommendedTradingCadence()['pollInterval'] as int;
  }

  bool _autoScannerEnabled() {
    return _intelligentScanner ||
        _enableProfitProtection ||
        _selectedPreset != null;
  }

  final List<String> strategies = [
    'Trend Following',
    'EMA Pullback ML',
    'Scalping',
    'Momentum Trading',
    'Mean Reversion',
    'Range Trading',
    'Breakout Trading',
    'Swing Trend DCA',
  ];

  @override
  void initState() {
    super.initState();
    _botIdController = TextEditingController(
      text: _isEditMode
          ? widget.botId!.trim()
          : 'bot_${DateTime.now().millisecondsSinceEpoch}',
    );
    _investmentAmountController = TextEditingController();

    // Initialize services
    _brokerService = BrokerCredentialsService();
    _commissionService = CommissionService();

    _initializeScreen();
    _commissionService.fetchCommissions();
  }

  Future<void> _initializeScreen() async {
    await _brokerService.fetchCredentials();
    if (!mounted) {
      return;
    }
    if (_isEditMode || _isCloneMode) {
      await _loadExistingBotConfig(preserveBotId: _isEditMode);
      if (!mounted) {
        return;
      }
      if (_isCloneMode && widget.promoteToLive) {
        await _alignActiveCredentialWithTradingMode(desiredMode: 'LIVE');
        if (!mounted) {
          return;
        }
      }
    } else {
      await _loadRiskSettings();
      if (!mounted) {
        return;
      }
      await _alignActiveCredentialWithTradingMode();
      if (!mounted) {
        return;
      }
      if (widget.focusTestedTemplates) {
        for (final credential in _brokerService.credentials) {
          if (credential.broker.toLowerCase().trim() == 'binance') {
            _brokerService.setActiveCredential(credential);
            break;
          }
        }
      }
    }
    await _fetchTradingData();
    await _loadTestedBotTemplates();
    if (widget.focusTestedTemplates && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final sectionContext = _testedTemplatesSectionKey.currentContext;
        if (sectionContext != null) {
          Scrollable.ensureVisible(
            sectionContext,
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeInOut,
            alignment: 0.08,
          );
        }
      });
    }
  }

  Future<void> _alignActiveCredentialWithTradingMode({
    String? desiredMode,
  }) async {
    final activeCredential = _brokerService.activeCredential;

    if (desiredMode == null && activeCredential != null) {
      await _persistTradingMode(activeCredential.isLive ? 'LIVE' : 'DEMO');
      return;
    }

    final tradingMode = (desiredMode ?? await _currentTradingMode())
        .trim()
        .toUpperCase();
    final expectsLive = tradingMode == 'LIVE';

    if (activeCredential != null && activeCredential.isLive == expectsLive) {
      return;
    }

    for (final credential in _brokerService.credentials) {
      if (credential.isLive == expectsLive) {
        _brokerService.setActiveCredential(credential);
        await _persistTradingMode(expectsLive ? 'LIVE' : 'DEMO');
        return;
      }
    }

    // Fallback: keep the flow usable by selecting the best available
    // credential and syncing trading mode to that credential.
    if (_brokerService.credentials.isNotEmpty) {
      final fallback = _brokerService.credentials.first;
      _brokerService.setActiveCredential(fallback);
      await _persistTradingMode(fallback.isLive ? 'LIVE' : 'DEMO');
    }
  }

  String _buildClonedBotId(String sourceBotId) {
    final sanitized = sourceBotId.trim().replaceAll(
      RegExp(r'[^a-zA-Z0-9_\-]'),
      '_',
    );
    final suffix = widget.promoteToLive ? 'live' : 'copy';
    return '${sanitized}_${suffix}_${DateTime.now().millisecondsSinceEpoch}';
  }

  Future<void> _loadExistingBotConfig({required bool preserveBotId}) async {
    setState(() {
      _isLoadingExistingBot = true;
      _errorMessage = null;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final sessionToken = prefs.getString('auth_token');
      if (sessionToken == null || sessionToken.isEmpty) {
        throw Exception('Session expired. Please login again.');
      }

      final response = await http
          .get(
            Uri.parse(
              '${EnvironmentConfig.apiUrl}/api/bot/config/$_configSourceBotId',
            ),
            headers: {
              'Content-Type': 'application/json',
              'X-Session-Token': sessionToken,
            },
          )
          .timeout(const Duration(seconds: 20));

      final data = jsonDecode(response.body);
      if (response.statusCode != 200 || data['success'] != true) {
        throw Exception(data['error'] ?? 'Failed to load bot configuration');
      }

      final config = Map<String, dynamic>.from(data['config'] ?? const {});
      final credentialId = (config['credentialId'] ?? '').toString().trim();
      if (credentialId.isNotEmpty) {
        for (final credential in _brokerService.credentials) {
          if (credential.credentialId == credentialId) {
            _brokerService.setActiveCredential(credential);
            break;
          }
        }
      }

      final symbols =
          (config['symbols'] as List?)
              ?.map((item) => item.toString())
              .where((item) => item.trim().isNotEmpty)
              .toList() ??
          <String>[];
      final allowedVolatility =
          (config['allowedVolatility'] as List?)
              ?.map((item) => item.toString())
              .where((item) => item.trim().isNotEmpty)
              .toList() ??
          _allowedVolatility;
      final profitProtection = Map<String, dynamic>.from(
        config['profitProtection'] as Map? ?? const {},
      );
      final status = Map<String, dynamic>.from(data['status'] as Map? ?? const {});
      final tradeAmount = config['tradeAmount'];
      final riskPercent =
          (config['riskPercent'] as num?)?.toDouble() ??
          ((config['riskPerTrade'] as num?)?.toDouble() ?? _riskPercent * 10) /
              10.0;
      final signalThreshold =
          (config['signalThreshold'] as num?)?.toInt() ??
          _defaultSignalThresholdForProfile(
            (config['managementProfile'] ?? _managementProfile).toString(),
          );
      final signalThresholdMode =
          (config['signalThresholdMode'] ?? 'auto').toString().toLowerCase();
        final copyTradingEnabled = config['copyTradingEnabled'] == true;
        final copyTradingSourceMode =
          (config['copyTradingSourceMode'] ??
              (copyTradingEnabled ? 'auto_success' : 'manual'))
            .toString()
            .trim();
        final copyTradingSourceBotId =
          (config['copyTradingSourceBotId'] ?? '').toString().trim();
      final copyTradingResolvedSourceBotId =
          (config['copyTradingResolvedSourceBotId'] ?? '').toString().trim();
      final copyTradingLastError =
          (status['copyTradingLastError'] ?? '').toString().trim();

      setState(() {
        _botIdController.text = preserveBotId
            ? (config['botId'] ?? widget.botId).toString()
            : _buildClonedBotId(
                (config['botId'] ?? widget.cloneFromBotId).toString(),
              );
        _selectedPreset =
            (config['selectedPreset'] ?? '').toString().trim().isEmpty
            ? null
            : (config['selectedPreset'] ?? '').toString().trim();
        _selectedStrategy = (config['strategy'] ?? _selectedStrategy)
            .toString();
        _selectedSymbols = symbols;
        _riskPercent = riskPercent;
        _maxOpenTrades =
            (config['maxOpenTrades'] as num?)?.toInt() ??
            (config['maxOpenPositions'] as num?)?.toInt() ??
            _maxOpenTrades;
        _maxDrawdownPercent =
            (config['maxDrawdownPercent'] as num?)?.toDouble() ??
            (config['drawdownPausePercent'] as num?)?.toDouble() ??
            _maxDrawdownPercent;
        _managementProfile = (config['managementProfile'] ?? _managementProfile)
            .toString();
        _manualSignalThreshold =
          signalThresholdMode == 'manual' ? signalThreshold : null;
        _allowedVolatility = allowedVolatility;
        _intelligentScanner = config['intelligentScanner'] == true;
        _topMoversEnabled = config['topMoversEnabled'] != false;
        _topMoversDirectTrading = config['topMoversDirectTrading'] == true;
        _enableProfitProtection =
            (profitProtection['enabled'] ?? _enableProfitProtection) == true;
        _profitProtectionActivationPercent =
            (profitProtection['activationPercent'] as num?)?.toDouble() ??
            _profitProtectionActivationPercent;
        _profitProtectionActivationMinProfit =
            (profitProtection['activationMinProfit'] as num?)?.toDouble() ??
            _profitProtectionActivationMinProfit;
        _profitProtectionMinLockedProfit =
          (profitProtection['minLockedProfit'] as num?)?.toDouble() ??
          _profitProtectionMinLockedProfit;
        _profitProtectionMarginTakeProfitPercent =
          (profitProtection['marginTakeProfitPercent'] as num?)?.toDouble() ??
          _profitProtectionMarginTakeProfitPercent;
        _profitProtectionRetracePercent =
            (profitProtection['retraceClosePercent'] as num?)?.toDouble() ??
            _profitProtectionRetracePercent;
        _profitProtectionSwitchOnReversal =
            (profitProtection['switchOnReversal'] ??
                _profitProtectionSwitchOnReversal) ==
            true;
        _profitProtectionAdaptiveByVolatility =
          (profitProtection['adaptiveByVolatility'] ??
            _profitProtectionAdaptiveByVolatility) ==
          true;
        _copyTradingEnabled = copyTradingEnabled;
        _copyTradingSourceMode = copyTradingSourceMode.isEmpty
            ? 'auto_success'
            : copyTradingSourceMode;
        _copyTradingSourceBotId =
            copyTradingSourceBotId.isEmpty ? null : copyTradingSourceBotId;
        _copyTradingResolvedSourceBotId = copyTradingResolvedSourceBotId.isEmpty
          ? null
          : copyTradingResolvedSourceBotId;
        _copyTradingSourceFeedback = copyTradingLastError.isEmpty
          ? null
          : copyTradingLastError;
        _investmentAmountController.text = tradeAmount == null
            ? ''
            : ((tradeAmount as num).toDouble() ==
                  (tradeAmount as num).toDouble().roundToDouble())
            ? (tradeAmount as num).toDouble().toStringAsFixed(0)
            : (tradeAmount as num).toDouble().toStringAsFixed(2);
          _applyCryptoSelectionSafetyDefaults();
        _blacklistedSymbols = ((data['blacklistedSymbols'] as List?)
                ?.map((e) => e.toString().trim().toUpperCase())
                .where((e) => e.isNotEmpty)
                .toSet()) ??
            {};
      });
      if (copyTradingEnabled) {
        await _loadCopyTradingSources();
      }
    } catch (e) {
      setState(() {
        _errorMessage = _isCloneMode
            ? 'Failed to load bot to clone: $e'
            : 'Failed to load existing bot: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingExistingBot = false;
        });
      }
    }
  }

  Future<void> _fetchTradingData() async {
    if (_activeBrokerName == 'fxcm') {
      _preloadFxcmSymbols();
      await _fetchCommodityData(showLoading: false);
      if (mounted) {
        setState(() {
          _testedBotTemplates = [];
          _isLoadingTestedBotTemplates = false;
        });
      }
      return;
    }

    await _fetchCommodityData();
  }

  Future<void> _loadTestedBotTemplates() async {
    if (!mounted) {
      return;
    }
    final activeBroker = (_brokerService.activeCredential?.broker ?? '').trim();
    if (_isCloneMode || activeBroker.isEmpty) {
      setState(() {
        _testedBotTemplates = [];
        _isLoadingTestedBotTemplates = false;
      });
      return;
    }

    setState(() {
      _isLoadingTestedBotTemplates = true;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final sessionToken = prefs.getString('auth_token') ?? '';
      if (sessionToken.isEmpty) {
        if (!mounted) return;
        setState(() {
          _testedBotTemplates = [];
          _isLoadingTestedBotTemplates = false;
        });
        return;
      }

      final response = await http
          .get(
            Uri.parse('${EnvironmentConfig.apiUrl}/api/bot/templates').replace(
              queryParameters: {'broker': activeBroker},
            ),
            headers: {'X-Session-Token': sessionToken},
          )
          .timeout(const Duration(seconds: 20));

      if (!mounted) {
        return;
      }

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final templates = List<Map<String, dynamic>>.from(
          data['templates'] ?? const <Map<String, dynamic>>[],
        );
        setState(() {
          _testedBotTemplates = templates;
          _isLoadingTestedBotTemplates = false;
        });
        return;
      }

      setState(() {
        _testedBotTemplates = [];
        _isLoadingTestedBotTemplates = false;
      });
    } catch (e) {
      debugPrint('Failed to load tested bot templates: $e');
      if (!mounted) {
        return;
      }
      setState(() {
        _testedBotTemplates = [];
        _isLoadingTestedBotTemplates = false;
      });
    }
  }

  String _copyTradingMarketName() {
    if (!_isBinanceBroker) {
      return '';
    }
    final marketName = (_brokerService.activeCredential?.server ?? 'spot')
        .toString()
        .trim()
        .toLowerCase();
    return marketName.isEmpty ? 'spot' : marketName;
  }

  Future<void> _loadCopyTradingSources() async {
    if (!mounted) {
      return;
    }
    final activeCredential = _brokerService.activeCredential;
    if (activeCredential == null || !_copyTradingEnabled) {
      setState(() {
        _copyTradingSources = [];
        _copyTradingSourceFeedback = null;
        _isLoadingCopyTradingSources = false;
      });
      return;
    }

    setState(() {
      _isLoadingCopyTradingSources = true;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final sessionToken = prefs.getString('auth_token') ?? '';
      if (sessionToken.isEmpty) {
        if (!mounted) return;
        setState(() {
          _copyTradingSources = [];
          _copyTradingSourceFeedback = 'Session expired. Please login again.';
          _isLoadingCopyTradingSources = false;
        });
        return;
      }

      final queryParameters = <String, String>{
        'broker': activeCredential.broker.trim(),
        'mode': activeCredential.isLive ? 'live' : 'demo',
      };
      if (_isBinanceBroker) {
        queryParameters['market'] = _copyTradingMarketName();
      }
      if (_isEditMode && widget.botId != null && widget.botId!.trim().isNotEmpty) {
        queryParameters['followerBotId'] = widget.botId!.trim();
      }
      final selectedSourceBotId = (_copyTradingSourceBotId ?? '').trim();
      if (selectedSourceBotId.isNotEmpty) {
        queryParameters['sourceBotId'] = selectedSourceBotId;
      }

      final response = await http
          .get(
            Uri.parse('${EnvironmentConfig.apiUrl}/api/bot/copy-trading-sources')
                .replace(queryParameters: queryParameters),
            headers: {'X-Session-Token': sessionToken},
          )
          .timeout(const Duration(seconds: 20));

      if (!mounted) {
        return;
      }

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final sources = List<Map<String, dynamic>>.from(
          data['sources'] ?? const <Map<String, dynamic>>[],
        );
        final selectedSource = Map<String, dynamic>.from(
          data['selectedSource'] as Map? ?? const {},
        );
        String? feedback;
        if (_copyTradingSourceMode == 'manual') {
          feedback = (selectedSource['eligibilityReason'] ?? '').toString().trim();
          if (feedback.isEmpty && sources.isEmpty) {
            feedback = (data['message'] ?? '').toString().trim();
          }
        } else {
          feedback = (data['message'] ?? '').toString().trim();
        }
        setState(() {
          _copyTradingSources = sources;
          _copyTradingSourceFeedback = feedback?.isEmpty ?? true ? null : feedback;
          _isLoadingCopyTradingSources = false;
        });
        return;
      }

      final data = jsonDecode(response.body);
      setState(() {
        _copyTradingSources = [];
        _copyTradingSourceFeedback =
            (data['error'] ?? 'Failed to load copy-trading sources').toString();
        _isLoadingCopyTradingSources = false;
      });
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _copyTradingSources = [];
        _copyTradingSourceFeedback = 'Failed to load copy-trading sources: $e';
        _isLoadingCopyTradingSources = false;
      });
    }
  }

  String _copyTradingSourceTemplateLabel(Map<String, dynamic> template) {
    final name = (template['name'] ?? template['botName'] ?? template['sourceBotId'])
        .toString()
        .trim();
    final sourceBotId = (template['sourceBotId'] ?? '').toString().trim();
    final symbolsPreview = List<String>.from(
      (template['symbolsPreview'] as List?) ??
          (template['symbols'] as List?) ??
          const <String>[],
    );
    final symbolsText = symbolsPreview.take(2).join(', ');

    if (symbolsText.isNotEmpty && sourceBotId.isNotEmpty && sourceBotId != name) {
      return '$name • $symbolsText • $sourceBotId';
    }
    if (symbolsText.isNotEmpty) {
      return '$name • $symbolsText';
    }
    return name;
  }

  String _defaultBotIdFromTemplate(Map<String, dynamic> template) {
    final base = (template['name'] ?? template['botName'] ?? template['sourceBotId'] ?? 'copied_bot')
        .toString()
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9_\-]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
    final prefix = base.isEmpty ? 'copied_bot' : base;
    return '${prefix}_${DateTime.now().millisecondsSinceEpoch}';
  }

  Future<void> _createBotFromTemplate(Map<String, dynamic> template) async {
    if (!_brokerService.hasCredentials || _brokerService.activeCredential == null) {
      _showError('Please connect a broker account first.');
      return;
    }

    final credential = _brokerService.activeCredential!;
    final templateBroker = (template['brokerName'] ?? '').toString().trim();
    final normalizedCredentialBroker = credential.broker.toLowerCase().trim();
    final normalizedTemplateBroker = templateBroker.toLowerCase().trim();
    if (normalizedTemplateBroker.isNotEmpty && normalizedTemplateBroker != normalizedCredentialBroker) {
      _showError(
        'Switch the active credential to $templateBroker before creating a copied bot from this template.',
      );
      return;
    }

    final sourceBotId = (template['sourceBotId'] ?? '').toString().trim();
    if (sourceBotId.isEmpty) {
      _showError('Selected template is missing a source bot reference.');
      return;
    }

    setState(() {
      _isCreating = true;
      _errorMessage = null;
      _successMessage = null;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final sessionToken = prefs.getString('auth_token') ?? '';
      if (sessionToken.isEmpty) {
        throw Exception('Session expired. Please login again.');
      }

      final templateSymbols = List<String>.from(
        (template['symbols'] as List?) ?? const <String>[],
      );
      final targetBotId = _botIdController.text.trim().isNotEmpty
          ? _botIdController.text.trim()
          : _defaultBotIdFromTemplate(template);
      if (_botIdController.text.trim().isEmpty) {
        _botIdController.text = targetBotId;
      }

      final botPayload = _buildBotPayload(credential);
      botPayload['botId'] = targetBotId;
      botPayload['name'] = targetBotId;
      botPayload['symbols'] = templateSymbols.isNotEmpty
          ? templateSymbols
          : List<String>.from(_selectedSymbols);
      botPayload['strategy'] = (template['strategy'] ?? botPayload['strategy']).toString();
      botPayload['managementProfile'] = (template['managementProfile'] ?? botPayload['managementProfile']).toString();
      botPayload['selectedPreset'] = template['selectedPreset'];
      botPayload['presetName'] = template['presetName'];
      botPayload['autoStart'] = false;
      botPayload['enabled'] = false;

      final createResponse = await http
          .post(
            Uri.parse('${EnvironmentConfig.apiUrl}/api/bot/create'),
            headers: {
              'Content-Type': 'application/json',
              'X-Session-Token': sessionToken,
            },
            body: jsonEncode(botPayload),
          )
          .timeout(const Duration(seconds: 90));

      final createData = jsonDecode(createResponse.body);
      if (createResponse.statusCode != 200 && createResponse.statusCode != 201) {
        throw Exception(
          createData['error'] ?? 'Failed to create bot: ${createResponse.statusCode}',
        );
      }

      final createdMode = ((botPayload['mode'] ?? 'demo').toString()).toUpperCase();
      await _persistTradingMode(createdMode);

      final createdBotId =
          (createData['botId']?.toString().trim().isNotEmpty ?? false)
          ? createData['botId'].toString().trim()
          : targetBotId;

      final syncResponse = await http
          .post(
            Uri.parse('${EnvironmentConfig.apiUrl}/api/bot/config/$createdBotId/sync-profile'),
            headers: {
              'Content-Type': 'application/json',
              'X-Session-Token': sessionToken,
            },
            body: jsonEncode({
              'sourceBotId': sourceBotId,
              'includeAdaptiveState': true,
            }),
          )
          .timeout(const Duration(seconds: 90));

      final syncData = jsonDecode(syncResponse.body);
      if (syncResponse.statusCode != 200 || syncData['success'] != true) {
        throw Exception(
          syncData['error'] ?? 'Failed to sync tested template onto new bot.',
        );
      }

      final startResponse = await http
          .post(
            Uri.parse('${EnvironmentConfig.apiUrl}/api/bot/start'),
            headers: {
              'Content-Type': 'application/json',
              'X-Session-Token': sessionToken,
            },
            body: jsonEncode({'botId': createdBotId, 'user_id': null}),
          )
          .timeout(const Duration(seconds: 90));

      final startData = _decodeJsonObject(startResponse.body);
      final startSucceeded = startResponse.statusCode == 200;
      final startDeniedByCapacity =
          startResponse.statusCode == 429 &&
          {
            'BINANCE_CAPACITY_LIMIT',
            'CAPACITY_LIMIT',
          }.contains(
            (startData['status'] ?? '').toString().trim().toUpperCase(),
          );
      String message;
      if (!startSucceeded) {
        final startErrorMessage =
            startData['error']?.toString() ?? 'Unknown startup failure';
        message =
            'Template bot created and synced successfully.\n'
            'Bot ID: $createdBotId\n'
            'Source template: ${template['name'] ?? sourceBotId}\n\n'
            '${startDeniedByCapacity
                ? 'Automatic start was skipped because bot capacity is full. '
                      'Stop another bot, then start this one from your bot list. '
                      'Reason: $startErrorMessage'
                : 'The bot did not start automatically: $startErrorMessage'}';
      } else {
        message =
            'Template bot created, synced, and started successfully.\n'
            'Bot ID: $createdBotId\n'
            'Source template: ${template['name'] ?? sourceBotId}\n\n'
            'The bot is now running with the tested configuration and adaptive state.';
      }

      final botService = Provider.of<BotService>(context, listen: false);
      await botService.fetchActiveBots(
        tradingMode: createdMode,
        force: true,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _successMessage = message;
      });
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) {
        setState(() {
          _isCreating = false;
        });
      }
    }
  }

  Future<void> _fetchCommodityData({bool showLoading = true}) async {
    if (showLoading) {
      setState(() => _isLoadingData = true);
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      final sessionToken = prefs.getString('auth_token') ?? '';
      final activeCredential = _brokerService.activeCredential;
      final queryParameters = <String, String>{};
      final activeBroker = activeCredential?.broker ?? _activeBrokerName;
      final normalizedBroker = activeBroker.toLowerCase().trim();
      if (activeBroker.isNotEmpty) {
        queryParameters['broker'] = activeBroker;
      }
      if (activeCredential != null && activeCredential.credentialId.isNotEmpty) {
        queryParameters['credential_id'] = activeCredential.credentialId;
      }
      final uri = Uri.parse(
        '${EnvironmentConfig.apiUrl}/api/commodities/list',
      ).replace(queryParameters: queryParameters.isEmpty ? null : queryParameters);
      final response = await http
          .get(
            uri,
            headers: {
              if (sessionToken.isNotEmpty) 'X-Session-Token': sessionToken,
            },
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final commoditiesList = data['commodities'] as Map? ?? {};
        final builtSymbols = normalizedBroker == 'binance'
            ? _buildSymbolsFromApiData(commoditiesList)
            : _curateFxcmSymbols(_buildSymbolsFromApiData(commoditiesList));

        if (builtSymbols.isNotEmpty) {
          setState(() {
            // Get market data for signal display (flat dict: {EURUSD: {signal, trend, ...}, ...})
            final marketDataResponse = data['marketData'] ?? {};
            commodityMarketData = _buildCommodityMarketDataIndex(
              marketDataResponse as Map,
              commoditiesList,
            );

            // Get commodities list for symbol selection (nested by category)
            tradingSymbols = builtSymbols;
            _selectedSymbols = _remapSelectedSymbolsToAvailable(
              tradingSymbols
                  .map((item) => item['symbol'])
                  .whereType<String>()
                  .toList(),
            );
            // Auto-select top recommended pairs for new bots (no preset applied yet)
            _autoSelectDefaultSymbols();
            _applyCryptoSelectionSafetyDefaults();
            _isLoadingData = false;
          });
          return;
        }
      }
      // Non-200 response or empty symbol list — fall through to use broker fallback symbols
      _loadFallbackSymbols();
    } catch (e) {
      print('Error fetching commodity data: $e');
      _loadFallbackSymbols();
    }
  }

  void _preloadFxcmSymbols() {
    setState(() {
      commodityMarketData = {};
      tradingSymbols = _curateFxcmSymbols(
        List<Map<String, String>>.from(_fxcmFallbackSymbols),
      );
      _selectedSymbols = _remapSelectedSymbolsToAvailable(
        tradingSymbols
            .map((item) => item['symbol'])
            .whereType<String>()
            .toList(),
      );
      // Auto-select top recommended pairs for new bots
      _autoSelectDefaultSymbols();
      _isLoadingData = false;
    });
  }

  void _loadFallbackSymbols() {
    setState(() {
      commodityMarketData = {}; // clear stale data so fallback items render with correct neutral styling
      tradingSymbols = _activeBrokerName == 'binance'
          ? List<Map<String, String>>.from(_binanceSymbols)
          : _activeBrokerName == 'fxcm'
          ? _curateFxcmSymbols(List<Map<String, String>>.from(_fxcmFallbackSymbols))
          : [
        {
          'symbol': 'BTCUSD',
          'name': '₿ Bitcoin (BTC/USD)',
          'category': 'Crypto',
        },
        {
          'symbol': 'ETHUSD',
          'name': 'Ethereum (ETH/USD)',
          'category': 'Crypto',
        },
        {
          'symbol': 'XAUUSD',
          'name': '🥇 Gold (XAU/USD)',
          'category': 'Precious Metals',
        },
        {
          'symbol': 'EURUSD',
          'name': '💱 Euro vs US Dollar',
          'category': 'Forex',
        },
        {
          'symbol': 'USDJPY',
          'name': '💱 US Dollar vs Japanese Yen',
          'category': 'Forex',
        },
        {
          'symbol': 'GBPUSD',
          'name': '💱 British Pound vs US Dollar',
          'category': 'Forex',
        },
        {
          'symbol': 'AUDUSD',
          'name': '💱 Australian Dollar vs US Dollar',
          'category': 'Forex',
        },
        {
          'symbol': 'USDCAD',
          'name': '💱 US Dollar vs Canadian Dollar',
          'category': 'Forex',
        },
        {
          'symbol': 'NVDA',
          'name': '📈 NVIDIA Corporation',
          'category': 'Stocks',
        },
        {'symbol': 'AAPL', 'name': '📈 Apple Inc.', 'category': 'Stocks'},
        {
          'symbol': 'MSFT',
          'name': '📈 Microsoft Corporation',
          'category': 'Stocks',
        },
      ];
      _selectedSymbols = _remapSelectedSymbolsToAvailable(
        tradingSymbols
            .map((item) => item['symbol'])
            .whereType<String>()
            .toList(),
      );
      // Auto-select top recommended pairs for new bots (no preset applied yet)
      _autoSelectDefaultSymbols();
      _isLoadingData = false;
    });
  }

  double _safeToDouble(dynamic value, [double fallback = 0.0]) {
    if (value is num) {
      return value.toDouble();
    }
    return double.tryParse(value?.toString() ?? '') ?? fallback;
  }

  List<Map<String, String>> _curateFxcmSymbols(
    List<Map<String, String>> symbols,
  ) {
    if (_activeBrokerName != 'fxcm') {
      return symbols;
    }

    final symbolsByBase = <String, Map<String, String>>{};
    for (final symbol in symbols) {
      final symbolCode = symbol['symbol'];
      if (symbolCode == null || symbolCode.isEmpty) {
        continue;
      }
      symbolsByBase[_normalizeSymbolBase(symbolCode)] = symbol;
    }

    final curated = <Map<String, String>>[];
    for (final preferredSymbol in _fxcmPreferredSymbolOrder) {
      final match = symbolsByBase[_normalizeSymbolBase(preferredSymbol)];
      if (match != null) {
        curated.add(match);
      }
    }

    return curated.isNotEmpty ? curated : symbols;
  }

  double _marketSignalStrength(Map<String, dynamic> marketData) {
    final rawValue =
        marketData['signalPercentage'] ??
        marketData['signalStrength'] ??
        marketData['signal_strength'] ??
        0;

    if (rawValue is num) {
      return rawValue.toDouble().clamp(0.0, 100.0);
    }

    return (double.tryParse(rawValue.toString()) ?? 0.0).clamp(0.0, 100.0);
  }

  Map<String, dynamic> _buildCommodityMarketDataIndex(
    Map marketDataResponse,
    Map commoditiesList,
  ) {
    final normalized = <String, dynamic>{};

    void storeAlias(String key, dynamic value) {
      final alias = key.trim();
      if (alias.isEmpty) {
        return;
      }
      normalized[alias] = value;
      normalized.putIfAbsent(_normalizeSymbolBase(alias), () => value);
    }

    marketDataResponse.forEach((key, value) {
      final entry = _normalizeMarketDataEntry(value);
      if (entry.isEmpty) {
        return;
      }
      storeAlias(key.toString(), entry);
      final analysisSymbol =
          entry['analysisSymbol']?.toString() ??
          entry['analysis_symbol']?.toString();
      if (analysisSymbol != null && analysisSymbol.isNotEmpty) {
        storeAlias(analysisSymbol, entry);
      }
    });

    commoditiesList.forEach((category, items) {
      if (items is! List) {
        return;
      }
      for (final item in items) {
        if (item is! Map) {
          continue;
        }
        final symbol = item['symbol']?.toString() ?? '';
        if (symbol.isEmpty) {
          continue;
        }

        final existing = _normalizeMarketDataEntry(normalized[symbol]);
        final merged = <String, dynamic>{
          ...item.map((key, value) => MapEntry(key.toString(), value)),
          ...existing,
        };
        storeAlias(symbol, merged);

        final analysisSymbol =
            item['analysis_symbol']?.toString() ??
            item['analysisSymbol']?.toString() ??
            '';
        if (analysisSymbol.isNotEmpty) {
          storeAlias(analysisSymbol, merged);
        }
      }
    });

    return normalized;
  }

  Map<String, dynamic> _resolveCommodityMarketEntry(Map<String, String> symbol) {
    final symbolCode = symbol['symbol'] ?? '';
    final analysisSymbol = symbol['analysisSymbol'] ?? '';
    final resolved = _normalizeMarketDataEntry(
      commodityMarketData[symbolCode] ??
          commodityMarketData[_normalizeSymbolBase(symbolCode)] ??
          (analysisSymbol.isNotEmpty ? commodityMarketData[analysisSymbol] : null) ??
          (analysisSymbol.isNotEmpty
              ? commodityMarketData[_normalizeSymbolBase(analysisSymbol)]
              : null),
    );

    if (resolved.isNotEmpty) {
      return resolved;
    }

    return {
      if (symbol['tradeabilityStatus'] != null)
        'tradeabilityStatus': symbol['tradeabilityStatus'],
      if (symbol['tradeabilityLabel'] != null)
        'tradeabilityLabel': symbol['tradeabilityLabel'],
      if (symbol['tradeabilityReason'] != null)
        'tradeabilityReason': symbol['tradeabilityReason'],
      if (analysisSymbol.isNotEmpty) 'analysisSymbol': analysisSymbol,
    };
  }

  Map<String, dynamic> _normalizeMarketDataEntry(dynamic rawEntry) {
    if (rawEntry is Map<String, dynamic>) {
      return rawEntry;
    }
    if (rawEntry is Map) {
      return rawEntry.map(
        (key, value) => MapEntry(key.toString(), value),
      );
    }
    return const <String, dynamic>{};
  }

  Color _marketSignalColor({
    required bool isBinanceSymbol,
    required String trend,
  }) {
    if (isBinanceSymbol) {
      return Colors.orangeAccent;
    }

    switch (trend.toUpperCase()) {
      case 'UP':
        return Colors.green;
      case 'DOWN':
        return Colors.red;
      case 'RANGING':
      case 'FLAT':
      case 'NEUTRAL':
      case 'CONSOLIDATING':
        return Colors.amber;
      default:
        return Colors.amber; // no data yet — show amber (neutral) not invisible grey
    }
  }

  String _marketTradeabilityStatus(Map<String, dynamic> marketData) {
    return (marketData['tradeabilityStatus'] ?? 'tradeable').toString();
  }

  String _marketTradeabilityLabel(Map<String, dynamic> marketData) {
    final status = _marketTradeabilityStatus(marketData);
    final explicitLabel = marketData['tradeabilityLabel']?.toString();
    if (explicitLabel != null && explicitLabel.isNotEmpty) {
      return explicitLabel;
    }
    switch (status) {
      case 'visible_only':
        return 'VISIBLE ONLY';
      case 'unavailable':
        return 'CLOSED/UNAVAILABLE';
      default:
        return 'TRADEABLE';
    }
  }

  Color _marketTradeabilityColor(Map<String, dynamic> marketData) {
    switch (_marketTradeabilityStatus(marketData)) {
      case 'visible_only':
        return Colors.orangeAccent;
      case 'unavailable':
        return Colors.redAccent;
      default:
        return Colors.greenAccent;
    }
  }

  /// Convert API response format to UI format
  List<Map<String, String>> _buildSymbolsFromApiData(Map apiData) {
    final symbols = <Map<String, String>>[];

    final categoryEmojis = {
      'forex': '💱',
      'forex_ndfs': '💱',
      'commodities': '⚡',
      'precious_metals': '🥇',
      'energy': '🛢️',
      'indices': '📊',
      'treasury': '🏦',
      'stocks': '📈',
      'stock_baskets': '🧺',
      'zar_pairs': '💱',
    };

    apiData.forEach((category, items) {
      if (items is List) {
        String categoryName = category;
        // Convert snake_case to Title Case
        categoryName = category
            .split('_')
            .map((w) => w[0].toUpperCase() + w.substring(1))
            .join(' ');

        final emoji = categoryEmojis[category] ?? '•';

        for (final item in items) {
          if (item is Map) {
            final symbol = item['symbol'] ?? '';
            final name = item['name'] ?? '';
            if (symbol.isNotEmpty && name.isNotEmpty) {
              symbols.add({
                'symbol': symbol,
                'name': '$emoji $name',
                'category': categoryName,
                'analysisSymbol':
                    item['analysis_symbol']?.toString() ??
                    item['analysisSymbol']?.toString() ??
                    '',
                'tradeabilityStatus':
                    item['tradeabilityStatus']?.toString() ?? '',
                'tradeabilityLabel':
                    item['tradeabilityLabel']?.toString() ?? '',
                'tradeabilityReason':
                    item['tradeabilityReason']?.toString() ?? '',
              });
            }
          }
        }
      }
    });

    return symbols;
  }

  @override
  void dispose() {
    _botIdController.dispose();
    _investmentAmountController.dispose();
    super.dispose();
  }

  Map<String, dynamic> _buildBotPayload(BrokerCredential credential) {
    final internalRiskPerTrade = (_riskPercent * 10)
        .clamp(5.0, 30.0)
        .toDouble();
    final maxPositionsPerSymbol = _recommendedMaxPositionsPerSymbol();
    final tradingMode = _recommendedTradingMode();
    final tradingInterval = _recommendedTradingInterval();
    final pollInterval = _recommendedPollInterval();
    final autoScanner = _autoScannerEnabled();
    final accountCurrency = credential.accountCurrency.toUpperCase();
    final binanceMarket = _isBinanceBroker ? _copyTradingMarketName() : null;

    return {
      'botId': _botIdController.text.trim(),
      'credentialId': credential.credentialId,
      'mode': credential.isLive ? 'live' : 'demo',
      if (binanceMarket != null) 'market': binanceMarket,
      'symbols': _selectedSymbols,
      'strategy': _selectedStrategy,
      'riskPercent': _riskPercent,
      'riskPerTrade': internalRiskPerTrade,
      'maxOpenTrades': _maxOpenTrades,
      'maxOpenPositions': _maxOpenTrades,
      'maxPositionsPerSymbol': maxPositionsPerSymbol,
      'maxDrawdownPercent': _maxDrawdownPercent,
      'drawdownPausePercent': _maxDrawdownPercent,
      'signalThresholdMode':
          _manualSignalThreshold == null ? 'auto' : 'manual',
      if (_manualSignalThreshold != null)
        'signalThreshold': _manualSignalThreshold,
      'tradingMode': tradingMode,
      'tradingInterval': tradingInterval,
      'pollInterval': pollInterval,
      if (_investmentAmountController.text.isNotEmpty)
        'tradeAmount': double.tryParse(_investmentAmountController.text),
      'displayCurrency': accountCurrency,
      if (_selectedPreset != null && _selectedPreset!.trim().isNotEmpty)
        'selectedPreset': _selectedPreset,
      if (_selectedPreset != null && _selectedPreset!.trim().isNotEmpty)
        'presetName': _smallAccountPresets[_selectedPreset!]?['name'],
      'allowedVolatility': _allowedVolatility,
      'autoSwitch': true,
      'dynamicSizing': true,
      'managementProfile': _managementProfile,
      'intelligentManagement': {
        'enabled': true,
        'profile': _managementProfile,
        'experienceLevel': _managementProfile,
        'autoSwitch': true,
        'dynamicSizing': true,
      },
      'enabled': !_isEditMode,
      'volatilityFilterEnabled': _volatilityFilterEnabled,
      'intelligentScanner': autoScanner,
      'topMoversEnabled': _topMoversEnabled,
      'topMoversDirectTrading': _topMoversDirectTrading,
      'copyTradingEnabled': _copyTradingEnabled,
      'copyTradingSourceMode': _copyTradingEnabled
          ? _copyTradingSourceMode
          : 'manual',
      if ((_copyTradingSourceBotId ?? '').trim().isNotEmpty)
        'copyTradingSourceBotId': _copyTradingSourceBotId!.trim(),
      // This screen calls /api/bot/start separately after creation,
      // so tell the backend NOT to auto-start to avoid a double-start race.
      'autoStart': false,
      'profitProtection': {
        'enabled': _enableProfitProtection,
        'activationPercent': _profitProtectionActivationPercent,
        'activationMinProfit': _profitProtectionActivationMinProfit,
        'minLockedProfit': _profitProtectionMinLockedProfit,
        'marginTakeProfitPercent': _profitProtectionMarginTakeProfitPercent,
        'retraceClosePercent': _profitProtectionRetracePercent,
        'switchOnReversal': _profitProtectionSwitchOnReversal,
        'adaptiveByVolatility': _profitProtectionAdaptiveByVolatility,
      },
    };
  }

  Future<void> _createAndStartBot({bool restartAfterSave = false}) async {
    // STEP 1: Check if broker is integrated
    if (!_brokerService.hasCredentials) {
      _showError('Please setup broker integration first!');

      // Show dialog with option to setup broker
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('⚠️ Broker Setup Required'),
            content: const Text(
              'You need to integrate your broker account before creating a bot. '
              'This ensures your bot can trade with verified credentials.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  // Navigate to broker integration screen
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => BrokerIntegrationScreen(
                        onBackPressed: () {
                          Navigator.pop(context);
                          // Refresh credentials after setup
                          _brokerService.fetchCredentials();
                        },
                      ),
                    ),
                  );
                },
                child: const Text('Setup Broker'),
              ),
            ],
          ),
        );
      }
      return;
    }

    if (_selectedSymbols.isEmpty && !_copyTradingEnabled) {
      _showError(_symbolSelectionError);
      return;
    }

    if (_copyTradingEnabled && _copyTradingSourceMode == 'manual') {
      final selectedSourceBotId = (_copyTradingSourceBotId ?? '').trim();
      if (selectedSourceBotId.isEmpty) {
        _showError('Choose a source bot for manual copy trading.');
        return;
      }
    }

    setState(() {
      _isCreating = true;
      _errorMessage = null;
      _successMessage = null;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final sessionToken = prefs.getString('auth_token');

      if (sessionToken == null) {
        throw Exception('Session expired. Please login again.');
      }

      if (!_isEditMode && (!_isCloneMode || widget.promoteToLive)) {
        await _alignActiveCredentialWithTradingMode(
          desiredMode: widget.promoteToLive ? 'LIVE' : null,
        );
      }

      // 🔴 FIX: Null-safe credential verification
      final credential = _brokerService.activeCredential;
      if (credential == null) {
        throw Exception(
          'Broker credential lost. Please setup broker integration again.',
        );
      }

      print(
        '🤖 Creating bot with broker credential: ${credential.credentialId}',
      );
      print('   Broker: ${credential.broker}');
      print('   Account: ${credential.accountNumber}');

      final fixedAmountWarning = _fixedTradeAmountWarningData(context);
      if (fixedAmountWarning != null) {
        final shouldContinue = await _confirmLowFixedTradeAmount(
          context,
          fixedAmountWarning,
        );
        if (!shouldContinue) {
          setState(() {
            _isCreating = false;
          });
          return;
        }
      }

      final botPayload = _buildBotPayload(credential);

      if (_isEditMode) {
        final updateResponse = await http
            .put(
              Uri.parse(
                '${EnvironmentConfig.apiUrl}/api/bot/config/${widget.botId}',
              ),
              headers: {
                'Content-Type': 'application/json',
                'X-Session-Token': sessionToken,
              },
              body: jsonEncode(botPayload),
            )
            .timeout(const Duration(seconds: 90));

        final updateData = jsonDecode(updateResponse.body);
        if (updateResponse.statusCode != 200 || updateData['success'] != true) {
          throw Exception(
            updateData['error'] ??
                'Failed to update bot: ${updateResponse.statusCode}',
          );
        }

        if (restartAfterSave) {
          final restartResponse = await http
              .post(
                Uri.parse('${EnvironmentConfig.apiUrl}/api/bot/start'),
                headers: {
                  'Content-Type': 'application/json',
                  'X-Session-Token': sessionToken,
                },
                body: jsonEncode({'botId': widget.botId, 'user_id': null}),
              )
              .timeout(const Duration(seconds: 90));

          final restartData = jsonDecode(restartResponse.body);
          if (restartResponse.statusCode != 200 ||
              restartData['success'] != true) {
            throw Exception(
              restartData['error'] ??
                  'Bot settings saved, but restart failed: ${restartResponse.statusCode}',
            );
          }
        }

        final botService = Provider.of<BotService>(context, listen: false);
        final currentTradingMode = await _currentTradingMode();
        await botService.fetchActiveBots(
          tradingMode: currentTradingMode,
          force: true,
        );

        if (!mounted) {
          return;
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              restartAfterSave
                  ? 'Bot updated and restarted successfully.'
                  : (updateData['message'] ?? 'Bot updated successfully.'),
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
        Navigator.of(context).pop(true);
        return;
      }

      final createResponse = await http
          .post(
            Uri.parse('${EnvironmentConfig.apiUrl}/api/bot/create'),
            headers: {
              'Content-Type': 'application/json',
              'X-Session-Token': sessionToken,
            },
            body: jsonEncode(botPayload),
          )
          .timeout(const Duration(seconds: 90));

      if (createResponse.statusCode != 200 &&
          createResponse.statusCode != 201) {
        final errorData = jsonDecode(createResponse.body);
        throw Exception(
          errorData['error'] ??
              'Failed to create bot: ${createResponse.statusCode}',
        );
      }

      final createData = jsonDecode(createResponse.body);
      final createdBotId =
          (createData['botId']?.toString().trim().isNotEmpty ?? false)
          ? createData['botId'].toString().trim()
          : _botIdController.text.trim();

      final createdMode = ((botPayload['mode'] ?? 'demo').toString()).toUpperCase();
      await _persistTradingMode(createdMode);

      if (createdBotId.isEmpty) {
        throw Exception(
          'Bot creation succeeded but no botId was returned by the backend.',
        );
      }

      print('✅ Bot created successfully: $createdBotId');

      // STEP 3: Start the bot immediately after creation
      print('🚀 Starting bot: $createdBotId');
      final startResponse = await http
          .post(
            Uri.parse('${EnvironmentConfig.apiUrl}/api/bot/start'),
            headers: {
              'Content-Type': 'application/json',
              'X-Session-Token': sessionToken,
            },
            body: jsonEncode({
              'botId': createdBotId,
              'user_id': null, // Will be extracted from session
            }),
          )
          .timeout(const Duration(seconds: 90));

      final startData = _decodeJsonObject(startResponse.body);
      final startSucceeded = startResponse.statusCode == 200;
      final startDeniedByCapacity =
          startResponse.statusCode == 429 &&
          {
            'BINANCE_CAPACITY_LIMIT',
            'CAPACITY_LIMIT',
          }.contains(
            (startData['status'] ?? '').toString().trim().toUpperCase(),
          );
      if (!startSucceeded) {
        final startErrorMessage =
            startData['error']?.toString() ?? 'Unknown startup failure';
        print('⚠️ Bot created but failed to start: $startErrorMessage');
        setState(() {
          _successMessage =
              'Bot created successfully! 🎉\n'
              'Bot ID: $createdBotId\n'
              '${_isBinanceBroker ? 'Pairs' : 'Symbols'}: ${_selectedSymbols.join(', ')}\n\n'
              '${startDeniedByCapacity
                  ? 'Automatic start was skipped because bot capacity is full. '
                        'Stop another bot, then start this one from your bot list. '
                        'Reason: $startErrorMessage'
                  : '⚠️ Bot was created but failed to start automatically. '
                        'Reason: $startErrorMessage\n'
                        'Please start it manually from your bot list after fixing the issue.'}';
        });
      } else {
        print('✅ Bot started successfully: ${startData['message']}');
        setState(() {
          _successMessage =
              'Bot created and started successfully! 🎉\n'
              'Bot ID: $createdBotId\n'
              '${_isBinanceBroker ? 'Pairs' : 'Symbols'}: ${_selectedSymbols.join(', ')}\n\n'
              'The bot is now actively trading in the background.';
        });
      }

      // Force-refresh bot list before navigating
      final botService = Provider.of<BotService>(context, listen: false);
      await botService.fetchActiveBots(
        tradingMode: createdMode,
        force: true,
      );

      // Show creation result immediately
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              startSucceeded
                  ? '✅ Bot created and started. It will appear in your bot list.'
                  : startDeniedByCapacity
                  ? '✅ Bot created. Auto-start was skipped because capacity is full.'
                  : '⚠️ Bot created, but automatic start failed. Check the warning on this screen.',
            ),
            backgroundColor: startSucceeded
                ? Colors.green
                : (startDeniedByCapacity ? Colors.blue : Colors.orange),
            duration: const Duration(seconds: 3),
          ),
        );
      }

      // Treat capacity-full as a successful creation flow so the new bot is visible.
      if (mounted && (startSucceeded || startDeniedByCapacity)) {
        Navigator.of(context).pop(true); // Return true to trigger bot list refresh in parent
      }
    } catch (e) {
      _showError('Error: ${e.toString()}');
    } finally {
      setState(() => _isCreating = false);
    }
  }

  void _showError(String message) {
    setState(() => _errorMessage = message);
  }

  Map<String, dynamic> _decodeJsonObject(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      if (decoded is Map) {
        return decoded.map(
          (key, value) => MapEntry(key.toString(), value),
        );
      }
    } catch (_) {
      return const <String, dynamic>{};
    }
    return const <String, dynamic>{};
  }

  // ========== AUTOMATED RISK MANAGEMENT METHODS ==========

  /// Load risk settings from backend API
  Future<void> _loadRiskSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final sessionToken = prefs.getString('auth_token') ?? '';
      final response = await http
          .get(
            Uri.parse('${EnvironmentConfig.apiUrl}/api/risk-settings/get'),
            headers: {
              if (sessionToken.isNotEmpty) 'X-Session-Token': sessionToken,
            },
          )
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final settings = data['settings'] ?? {};
        setState(() {
          _riskPercent = (settings['risk_percent'] ?? 2.0).toDouble();
          _maxOpenTrades = (settings['max_open_trades'] ?? 3) as int;
          _maxDrawdownPercent = (settings['max_drawdown_percent'] ?? 20.0)
              .toDouble();
        });
      }
    } catch (e) {
      print('Error loading risk settings: $e');
    }
  }

  /// Save risk settings to backend API
  Future<void> _saveRiskSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final sessionToken = prefs.getString('auth_token') ?? '';
      final response = await http
          .post(
            Uri.parse('${EnvironmentConfig.apiUrl}/api/risk-settings/save'),
            headers: {
              'Content-Type': 'application/json',
              if (sessionToken.isNotEmpty) 'X-Session-Token': sessionToken,
            },
            body: jsonEncode({
              'risk_percent': _riskPercent,
              'max_open_trades': _maxOpenTrades,
              'max_drawdown_percent': _maxDrawdownPercent,
            }),
          )
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              '✅ Risk settings saved! Bot will use automatic lot sizing.',
            ),
            duration: Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Error saving risk settings: $e'),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  /// Get session ID from SharedPreferences
  Future<String> _getSessionId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('session_id') ?? '';
  }

  @override
  Widget build(BuildContext context) {
    final currencyProvider = context.watch<CurrencyProvider>();

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            LogoWidget(size: 40, showText: false),
            const SizedBox(width: 12),
            const Expanded(child: Text('Bot Configuration')),
          ],
        ),
        backgroundColor: Colors.grey[900],
        elevation: 0,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<AppCurrency>(
                value: currencyProvider.currency,
                dropdownColor: Colors.grey[900],
                icon: const Icon(Icons.currency_exchange, color: Colors.white),
                style: const TextStyle(color: Colors.white),
                items: AppCurrency.values
                    .map(
                      (currency) => DropdownMenuItem<AppCurrency>(
                        value: currency,
                        child: Text(
                          _currencyCode(currency),
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value != null) {
                    currencyProvider.setCurrency(value);
                  }
                },
              ),
            ),
          ),
          TextButton.icon(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => const BotDashboardScreen(),
                ),
              );
            },
            icon: const Icon(Icons.dashboard),
            label: const Text('Dashboard'),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Success Banner
            if (_successMessage != null)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.2),
                  border: Border.all(color: Colors.green),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.check_circle,
                      color: Colors.green,
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _successMessage!,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 16),
                      onPressed: () => setState(() => _successMessage = null),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
              ),

            // Error Banner
            if (_errorMessage != null)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.2),
                  border: Border.all(color: Colors.red),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error, color: Colors.red, size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 16),
                      onPressed: () => setState(() => _errorMessage = null),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 12),

            // Recommended Settings Info
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF0066FF).withOpacity(0.12),
                border: Border.all(
                  color: const Color(0xFF0066FF).withOpacity(0.4),
                ),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Icon(Icons.auto_awesome, color: Color(0xFF64B5F6), size: 20),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Recommended settings pre-applied: 2% risk, 3 max trades, 20% max drawdown, Trend Following strategy.',
                      style: TextStyle(color: Colors.white70, fontSize: 11),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // ========== SMALL ACCOUNT PRESETS ==========
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.amber.withOpacity(0.12),
                    Colors.orange.withOpacity(0.08),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                border: Border.all(color: Colors.amber.withOpacity(0.5)),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Builder(
                    builder: (context) {
                      final currencyCode = _activeAccountCurrencyCode(context);
                      final starterRange = _formatPresetRange(
                        10,
                        1000,
                        currencyCode,
                      );
                      return Row(
                        children: [
                          const Icon(
                            Icons.rocket_launch,
                            color: Colors.amber,
                            size: 22,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Small Account Presets',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.amber,
                                  ),
                                ),
                                Text(
                                  'One-tap setup for $starterRange starter accounts',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey[400],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (_selectedPreset != null)
                            IconButton(
                              icon: const Icon(
                                Icons.clear,
                                size: 18,
                                color: Colors.grey,
                              ),
                              onPressed: () =>
                                  setState(() => _selectedPreset = null),
                              tooltip: 'Clear preset',
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                            ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  if (_isBinanceBroker) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF0B90B).withOpacity(0.10),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFF0B90B).withOpacity(0.4)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.info_outline, size: 14, color: Color(0xFFF0B90B)),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'These presets set strategy & risk settings. Use the Binance Quick Actions above to select pairs. '
                              'Tapping 🔥 Weekend or ₿ Crypto will also set BTCUSDT + ETHUSDT.',
                              style: TextStyle(fontSize: 11, color: Colors.grey[300]),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _smallAccountPresets.entries.map((entry) {
                      final key = entry.key;
                      final preset = entry.value;
                      final isSelected = _selectedPreset == key;
                      return ActionChip(
                        avatar: Text(
                          preset['icon'] as String,
                          style: const TextStyle(fontSize: 14),
                        ),
                        label: Text(
                          preset['name'] as String,
                          style: TextStyle(
                            fontWeight: isSelected
                                ? FontWeight.bold
                                : FontWeight.normal,
                            color: isSelected ? Colors.amber : Colors.white70,
                          ),
                        ),
                        backgroundColor: isSelected
                            ? Colors.amber.withOpacity(0.25)
                            : Colors.grey[800]?.withOpacity(0.6),
                        side: BorderSide(
                          color: isSelected
                              ? Colors.amber
                              : Colors.grey.withOpacity(0.3),
                          width: isSelected ? 2 : 1,
                        ),
                        onPressed: () => _applySmallAccountPreset(key),
                      );
                    }).toList(),
                  ),
                  if (_selectedPreset != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.black26,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Builder(
                            builder: (context) {
                              final currencyCode = _activeAccountCurrencyCode(
                                context,
                              );
                              final selectedPreset =
                                  _smallAccountPresets[_selectedPreset]!;
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    selectedPreset['description'] as String,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Colors.white70,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    _presetRecommendedRangeText(
                                      _selectedPreset!,
                                      currencyCode,
                                    ),
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.amber[200],
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                          const SizedBox(height: 8),
                          ...(_smallAccountPresets[_selectedPreset]!['tips']
                                  as List)
                              .map(
                                (tip) => Padding(
                                  padding: const EdgeInsets.only(bottom: 3),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        '• ',
                                        style: TextStyle(
                                          color: Colors.amber,
                                          fontSize: 11,
                                        ),
                                      ),
                                      Expanded(
                                        child: Text(
                                          tip as String,
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: Colors.grey[300],
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Bot Rental Agreement Image
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.blue, width: 2),
                borderRadius: BorderRadius.circular(8),
                color: Colors.blue.withOpacity(0.05),
              ),
              child: Row(
                children: [
                   Image.asset(
                     'assets/images/bot_rental.png',
                     height: 100,
                     width: 100,
                     fit: BoxFit.contain,
                     errorBuilder: (context, error, stackTrace) => Container(
                       height: 100,
                       width: 100,
                       color: Colors.grey[800],
                       child: const Icon(
                         Icons.image_not_supported,
                         color: Colors.grey,
                       ),
                     ),
                   ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Your Bot Rental Agreement',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Configure your rental bot settings below',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[400],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Bot Configuration Card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Bot Configuration',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 16),

                    // Broker Information Section
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.green),
                        borderRadius: BorderRadius.circular(8),
                        color: Colors.green.withOpacity(0.05),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.account_balance,
                                color: Colors.green,
                                size: 24,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Connected Broker',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      _brokerService.activeCredential != null
                                          ? '${_brokerService.activeCredential!.broker} - Account #${_brokerService.activeCredential!.accountNumber}'
                                          : 'No broker connected',
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    if (_brokerService.activeCredential !=
                                        null) ...[
                                      const SizedBox(height: 4),
                                      Text(
                                        '${_credentialModeLabel(_brokerService.activeCredential!)} • ${_brokerService.activeCredential!.accountCurrency} • ${_credentialStatusText(_brokerService.activeCredential!)}',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color:
                                              _brokerService
                                                  .activeCredential!
                                                  .isHealthy
                                              ? Colors.grey[300]
                                              : Colors.orange[300],
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              ElevatedButton.icon(
                                onPressed: () {
                                  Navigator.of(context)
                                      .push(
                                        MaterialPageRoute(
                                          builder: (context) =>
                                              const BrokerIntegrationScreen(),
                                        ),
                                      )
                                      .then((_) {
                                        setState(() {
                                          _brokerService.fetchCredentials();
                                        });
                                      });
                                },
                                icon: const Icon(Icons.edit, size: 18),
                                label: const Text('Change'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.green.withOpacity(
                                    0.3,
                                  ),
                                  foregroundColor: Colors.green,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          // Show list of saved credentials if multiple exist
                          if (_brokerService.credentials.length > 1)
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Divider(),
                                const SizedBox(height: 8),
                                const Text(
                                  'Your Saved Credentials',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: _brokerService.credentials.map((
                                    cred,
                                  ) {
                                    final isActive =
                                        cred.credentialId ==
                                        _brokerService
                                            .activeCredential
                                            ?.credentialId;
                                    final modeLabel = _credentialModeLabel(
                                      cred,
                                    );
                                    final modeColor = _credentialModeColor(
                                      cred,
                                    );
                                    return FilterChip(
                                      label: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            '${cred.broker} #${cred.accountNumber} ',
                                          ),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 6,
                                              vertical: 1,
                                            ),
                                            decoration: BoxDecoration(
                                              color: modeColor.withOpacity(0.2),
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                            ),
                                            child: Text(
                                              modeLabel,
                                              style: TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold,
                                                color: modeColor,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          Text(
                                            cred.accountCurrency,
                                            style: const TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          Text(
                                            cred.isHealthy
                                                ? _formatCompactCurrency(
                                                    cred.cachedBalance,
                                                    cred.accountCurrency,
                                                  )
                                                : 'STALE',
                                            style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.w600,
                                              color: cred.isHealthy
                                                  ? Colors.white70
                                                  : Colors.orangeAccent,
                                            ),
                                          ),
                                        ],
                                      ),
                                      selected: isActive,
                                      onSelected: (selected) {
                                        if (selected) {
                                          setState(() {
                                            _brokerService.setActiveCredential(
                                              cred,
                                            );
                                          });
                                          _fetchTradingData();
                                        }
                                      },
                                      backgroundColor: Colors.grey.withOpacity(
                                        0.2,
                                      ),
                                      selectedColor: Colors.green.withOpacity(
                                        0.3,
                                      ),
                                    );
                                  }).toList(),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    if (!_isEditMode && !_isCloneMode && _brokerService.activeCredential != null) ...[
                      Container(
                        key: _testedTemplatesSectionKey,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.orange.withOpacity(0.5)),
                          borderRadius: BorderRadius.circular(8),
                          color: Colors.orange.withOpacity(0.06),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.auto_awesome, color: Colors.orange),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Reusable ${_brokerService.activeCredential!.broker} Templates',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      Text(
                                        'Create a new ${_brokerService.activeCredential!.broker} bot from one of your existing bots. The app will create it, copy the config and adaptive state, then start it.',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey[300],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                TextButton.icon(
                                  onPressed: _isLoadingTestedBotTemplates
                                      ? null
                                      : _loadTestedBotTemplates,
                                  icon: const Icon(Icons.refresh, size: 18),
                                  label: const Text('Refresh'),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            if (_isLoadingTestedBotTemplates)
                              const Center(child: CircularProgressIndicator())
                            else if (_testedBotTemplates.isEmpty)
                              Text(
                                'No ${_brokerService.activeCredential!.broker} source bots are available yet. Create or run at least one ${_brokerService.activeCredential!.broker} bot first, then it will appear here as a reusable template.',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[400],
                                ),
                              )
                            else
                              SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: Row(
                                  children: _testedBotTemplates.map((template) {
                                    final symbolsPreview = List<String>.from(
                                      (template['symbolsPreview'] as List?) ?? const <String>[],
                                    );
                                    final isTested = template['isTested'] == true;
                                    final templateBroker = (template['brokerName'] ?? _brokerService.activeCredential!.broker)
                                        .toString();
                                    final normalizedTemplateBroker = templateBroker.toLowerCase().trim();
                                    return Container(
                                      width: 300,
                                      margin: const EdgeInsets.only(right: 12),
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: Colors.black.withOpacity(0.12),
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(color: Colors.white12),
                                      ),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  (template['name'] ?? template['botName'] ?? template['sourceBotId']).toString(),
                                                  style: const TextStyle(
                                                    fontSize: 15,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ),
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                decoration: BoxDecoration(
                                                  color: (isTested ? Colors.green : Colors.blueGrey).withOpacity(0.18),
                                                  borderRadius: BorderRadius.circular(12),
                                                ),
                                                child: Text(
                                                  isTested ? 'Tested' : 'Template',
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.w700,
                                                    color: isTested ? Colors.greenAccent : Colors.white70,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 8),
                                          Text(
                                            'Preset: ${((template['presetName'] ?? '').toString().trim().isEmpty ? 'Custom' : template['presetName'])} • Profile: ${template['managementProfile'] ?? 'n/a'}',
                                            style: TextStyle(fontSize: 12, color: Colors.grey[300]),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            'Trades: ${template['totalTrades'] ?? 0} • Win rate: ${template['winRate'] ?? 0}% • Profit: ${template['totalProfit'] ?? 0}',
                                            style: TextStyle(fontSize: 12, color: Colors.grey[300]),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            normalizedTemplateBroker == 'binance'
                                                ? 'Market: ${template['binanceMarket'] ?? 'spot'} • Effective trade amount: ${template['effectiveTradeAmount'] ?? 0}'
                                                : 'Broker: $templateBroker • Effective trade amount: ${template['effectiveTradeAmount'] ?? 0}',
                                            style: TextStyle(fontSize: 12, color: Colors.grey[300]),
                                          ),
                                          const SizedBox(height: 8),
                                          Text(
                                            symbolsPreview.isEmpty
                                                ? 'Symbols will be copied from the source bot.'
                                                : 'Symbols: ${symbolsPreview.join(', ')}${(template['symbolsCount'] ?? symbolsPreview.length) > symbolsPreview.length ? ' +' : ''}',
                                            style: TextStyle(fontSize: 12, color: Colors.grey[400]),
                                          ),
                                          const SizedBox(height: 12),
                                          SizedBox(
                                            width: double.infinity,
                                            child: ElevatedButton.icon(
                                              onPressed: _isCreating
                                                  ? null
                                                  : () => _createBotFromTemplate(template),
                                              icon: const Icon(Icons.flash_on, size: 18),
                                                label: const Text('Create From Template'),
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  }).toList(),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // Bot ID and Strategy (Side by Side)
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _botIdController,
                            enabled: !_isEditMode,
                            decoration: InputDecoration(
                              labelText: 'Bot ID',
                              hintText: (_isEditMode || _isCloneMode)
                                  ? null
                                  : 'bot_trend_1',
                              helperText: _isEditMode
                                  ? 'Bot ID stays fixed when reconfiguring an existing bot.'
                                  : (_isCloneMode
                                        ? (widget.promoteToLive
                                              ? 'This live bot is prefilled from your demo bot settings. Change the bot ID if you want a custom live name.'
                                              : 'This is a cloned setup. Change the bot ID if you want a custom copy name.')
                                        : null),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            value: _selectedStrategy,
                            decoration: InputDecoration(
                              labelText: 'Strategy',
                              helperText: _isCryptoOnlySelection
                                  ? 'Crypto-only baskets stay on slower trend or swing strategies.'
                                  : null,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            items: _availableStrategies
                                .map(
                                  (strategy) => DropdownMenuItem(
                                    value: strategy,
                                    child: Text(strategy),
                                  ),
                                )
                                .toList(),
                            onChanged: (value) {
                              if (value != null) {
                                setState(() {
                                  _selectedStrategy = value;
                                  _applyCryptoSelectionSafetyDefaults();
                                });
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Trading Symbols Selection
                    Text(
                      '$_symbolSectionTitle (${_selectedSymbols.length})',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    if (_brokerService.activeCredential != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Broker account: ${_brokerService.activeCredential!.broker} • ${_brokerService.activeCredential!.accountNumber} • ${_credentialModeLabel(_brokerService.activeCredential!)} • ${_brokerService.activeCredential!.accountCurrency}',
                        style: TextStyle(fontSize: 12, color: Colors.grey[400]),
                      ),
                      if (!_brokerService.activeCredential!.isHealthy)
                        Text(
                          'This credential has no warmed cache yet. It may show as disconnected until you test the connection or start a bot on it.',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.orange[300],
                          ),
                        ),
                    ],
                    if (_isBinanceBroker) ...[
                      const SizedBox(height: 10),
                      _buildBinanceSetupInsights(),
                      const SizedBox(height: 10),
                      TextField(
                        onChanged: (value) {
                          setState(() {
                            _binanceSymbolSearchQuery = value;
                          });
                        },
                        decoration: InputDecoration(
                          labelText: 'Search Binance pairs',
                          hintText: 'BTC, ETH, SOL, LINK, BTC quote...',
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon: _binanceSymbolSearchQuery.isEmpty
                              ? null
                              : IconButton(
                                  onPressed: () {
                                    setState(() {
                                      _binanceSymbolSearchQuery = '';
                                    });
                                  },
                                  icon: const Icon(Icons.clear),
                                ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: _binanceQuoteFilters
                              .map((quote) {
                            return Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: ChoiceChip(
                                label: Text(quote),
                                selected: _selectedBinanceQuoteFilter == quote,
                                onSelected: (_) {
                                  setState(() {
                                    _selectedBinanceQuoteFilter = quote;
                                  });
                                },
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                      const SizedBox(height: 8),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: _binanceCategoryFilters.map((category) {
                            return Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: ChoiceChip(
                                label: Text(category),
                                selected: _selectedBinanceCategoryFilter == category,
                                onSelected: (_) {
                                  setState(() {
                                    _selectedBinanceCategoryFilter = category;
                                  });
                                },
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    if (!_isBinanceBroker)
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children:
                              [
                                'All',
                                'Stable',
                                'Moderate',
                                'High Volatility',
                              ].map((bucket) {
                                return Padding(
                                  padding: const EdgeInsets.only(right: 8),
                                  child: ChoiceChip(
                                    label: Text(bucket),
                                    selected:
                                        _selectedTraditionalVolatilityFilter ==
                                        bucket,
                                    onSelected: (_) {
                                      setState(() {
                                        _selectedTraditionalVolatilityFilter =
                                            bucket;
                                      });
                                    },
                                  ),
                                );
                              }).toList(),
                        ),
                      ),
                    const SizedBox(height: 8),
                    Text(
                      _isBinanceBroker
                          ? 'Showing ${_filteredTradingSymbols.length} of ${tradingSymbols.length} Binance pairs. Quote: ${_selectedBinanceQuoteFilter == 'All' ? 'any' : _selectedBinanceQuoteFilter}, category: ${_selectedBinanceCategoryFilter == 'All' ? 'any' : _selectedBinanceCategoryFilter}${_binanceSymbolSearchQuery.trim().isEmpty ? '' : ', search: "${_binanceSymbolSearchQuery.trim()}"'}.'
                          : _selectedTraditionalVolatilityFilter == 'All'
                              ? '${tradingSymbols.length} symbols available, grouped by recommended markets first and then ordered from stable to high volatility.'
                              : 'Showing ${_filteredTradingSymbols.length} of ${tradingSymbols.length} symbols in the \'${_selectedTraditionalVolatilityFilter}\' category.',
                      style: TextStyle(fontSize: 11, color: Colors.grey[400]),
                    ),
                    if (_hiddenSelectedSymbolCount > 0)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          _isBinanceBroker
                              ? '$_hiddenSelectedSymbolCount selected pair(s) are outside the current Binance filters and remain selected.'
                              : '$_hiddenSelectedSymbolCount selected symbol(s) are outside this filter and remain selected.',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.orange[300],
                          ),
                        ),
                      ),
                    const SizedBox(height: 8),
                    Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: _isLoadingData
                            ? const Center(child: CircularProgressIndicator())
                            : SizedBox(
                                height: 350,
                                child: ListView.builder(
                                  itemCount: _filteredTradingSymbols.length,
                                  itemBuilder: (context, index) {
                                  try {
                                    final symbol =
                                      _filteredTradingSymbols[index];
                                    final groupTitle = !_isBinanceBroker
                                      ? _traditionalGroupTitle(symbol)
                                      : '';
                                    final previousGroupTitle =
                                      !_isBinanceBroker && index > 0
                                      ? _traditionalGroupTitle(
                                          _filteredTradingSymbols[index - 1],
                                        )
                                      : '';
                                    final showGroupHeader =
                                      !_isBinanceBroker &&
                                      groupTitle != previousGroupTitle;
                                    final symbolCode =
                                      symbol['symbol'] ?? 'Unknown';
                                    final isBinanceSymbol = _isBinanceBroker;
                                    final traditionalBucket =
                                      _traditionalVolatilityBucket(
                                      symbolCode,
                                      );
                                    final traditionalBucketColor =
                                      _traditionalVolatilityColor(
                                      traditionalBucket,
                                      );

                                    // Get market data for this symbol directly (API now uses correct keys)
                                    final marketData =
                                      _resolveCommodityMarketEntry(symbol);
                                    final binanceData =
                                      _binanceAnalyticsForSymbol(symbolCode);
                                    final trend =
                                      marketData['trend'] ?? 'NEUTRAL';
                                    final signalColor = _marketSignalColor(
                                    isBinanceSymbol: isBinanceSymbol,
                                    trend: trend.toString(),
                                    );
                                    final isBullish = isBinanceSymbol
                                      ? true
                                      : trend == 'UP';
                                    final change = _safeToDouble(
                                    marketData['change'],
                                    );
                                    final signalStrength =
                                      _marketSignalStrength(marketData);
                                    final tradeabilityStatus =
                                      _marketTradeabilityStatus(marketData);
                                    final tradeabilityLabel =
                                      _marketTradeabilityLabel(marketData);
                                    final tradeabilityColor =
                                      _marketTradeabilityColor(marketData);
                                    final tradeabilityReason =
                                      marketData['tradeabilityReason']?.toString();
                                    final isUnavailableFxcmSymbol =
                                      !isBinanceSymbol &&
                                      tradeabilityStatus == 'unavailable';
                                    final edgePct = _safeToDouble(
                                    binanceData['edgePct'],
                                    );
                                    final winRate = _safeToDouble(
                                    binanceData['winRate'],
                                    );
                                    final signal = isBinanceSymbol
                                      ? 'EDGE ${edgePct.toStringAsFixed(1)}%'
                                      : (marketData['signal'] ??
                                        '🟡 NEUTRAL');
                                    final visiblePercentageLabel =
                                      isBinanceSymbol
                                      ? '${edgePct.toStringAsFixed(1)}% edge • ${winRate.toStringAsFixed(0)}% win'
                                      : signalStrength > 0
                                      ? '${signalStrength.toStringAsFixed(signalStrength >= 10 ? 0 : 1)}% signal'
                                      : '${change > 0 ? '+' : ''}${change.toStringAsFixed(2)}%';
                                    final recommendation = isBinanceSymbol
                                      ? '${binanceData['analysis'] ?? 'Selected Binance pair will follow your strategy.'} | Est. win rate ${winRate.toStringAsFixed(0)}%'
                                      : isUnavailableFxcmSymbol &&
                                              tradeabilityReason != null &&
                                              tradeabilityReason.isNotEmpty
                                      ? tradeabilityReason
                                      : (marketData['recommendation'] ??
                                        'No data available');
                                    final volatility = isBinanceSymbol
                                      ? '${binanceData['risk'] ?? 'Medium'} risk'
                                      : (marketData['volatility'] ??
                                        'Unknown');

                                    return Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        if (showGroupHeader)
                                          Padding(
                                            padding: const EdgeInsets.only(
                                              top: 6,
                                              bottom: 8,
                                            ),
                                            child: Text(
                                              groupTitle,
                                              style: TextStyle(
                                                color: Colors.orange[200],
                                                fontSize: 12,
                                                fontWeight: FontWeight.w700,
                                                letterSpacing: 0.3,
                                              ),
                                            ),
                                          ),
                                        Container(
                                          margin: const EdgeInsets.only(bottom: 8),
                                          decoration: BoxDecoration(
                                            border: Border.all(
                                              color: signalColor.withOpacity(
                                                marketData.isEmpty ? 0.55 : 0.35,
                                              ),
                                            ),
                                            borderRadius: BorderRadius.circular(8),
                                            color: signalColor.withOpacity(
                                              marketData.isEmpty ? 0.14 : 0.06,
                                            ),
                                          ),
                                          child: CheckboxListTile(
                                            value: _isSymbolSelected(symbolCode),
                                            onChanged: isUnavailableFxcmSymbol
                                                ? null
                                                : (value) {
                                                    setState(() {
                                                      if (value ?? false) {
                                                        if (!_isSymbolSelected(symbolCode)) {
                                                          _selectedSymbols.add(symbolCode);
                                                        }
                                                      } else {
                                                        _selectedSymbols.removeWhere(
                                                          (selected) =>
                                                              _normalizeSymbolBase(selected) ==
                                                              _normalizeSymbolBase(symbolCode),
                                                        );
                                                      }
                                                      _applyCryptoSelectionSafetyDefaults();
                                                    });
                                                  },
                                            title: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(symbol['name'] ?? symbolCode),
                                                const SizedBox(height: 6),
                                                Wrap(
                                                  spacing: 8,
                                                  runSpacing: 6,
                                                  children: [
                                                    Container(
                                                      padding: const EdgeInsets.symmetric(
                                                        horizontal: 8,
                                                        vertical: 4,
                                                      ),
                                                      decoration: BoxDecoration(
                                                        color: signalColor.withOpacity(0.18),
                                                        border: Border.all(color: signalColor),
                                                        borderRadius: BorderRadius.circular(4),
                                                      ),
                                                      child: Text(
                                                        signal,
                                                        style: TextStyle(
                                                          color: signalColor,
                                                          fontSize: 11,
                                                          fontWeight: FontWeight.bold,
                                                        ),
                                                      ),
                                                    ),
                                                    Container(
                                                      padding: const EdgeInsets.symmetric(
                                                        horizontal: 8,
                                                        vertical: 4,
                                                      ),
                                                      decoration: BoxDecoration(
                                                        color: signalColor.withOpacity(0.12),
                                                        borderRadius: BorderRadius.circular(4),
                                                      ),
                                                      child: Text(
                                                        visiblePercentageLabel,
                                                        style: TextStyle(
                                                          color: signalColor,
                                                          fontWeight: FontWeight.bold,
                                                          fontSize: 11,
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ],
                                            ),
                                            subtitle: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Wrap(
                                                  spacing: 8,
                                                  runSpacing: 6,
                                                  children: [
                                                    Text(
                                                      symbol['category'] ?? 'General',
                                                      style: const TextStyle(fontSize: 11),
                                                    ),
                                                    if (isBinanceSymbol)
                                                      Container(
                                                        padding: const EdgeInsets.symmetric(
                                                          horizontal: 6,
                                                          vertical: 2,
                                                        ),
                                                        decoration: BoxDecoration(
                                                          color: Colors.blueAccent.withOpacity(0.14),
                                                          borderRadius: BorderRadius.circular(3),
                                                          border: Border.all(
                                                            color: Colors.blueAccent.withOpacity(0.35),
                                                          ),
                                                        ),
                                                        child: Text(
                                                          '${_binanceQuoteAsset(symbolCode)} quote',
                                                          style: const TextStyle(
                                                            fontSize: 9,
                                                            color: Colors.blueAccent,
                                                            fontWeight: FontWeight.w700,
                                                          ),
                                                        ),
                                                      ),
                                                    // Micro-account warning badge for expensive symbols
                                                    if (isBinanceSymbol &&
                                                        const {'BTCUSDT', 'BNBUSDT', 'SOLUSDT'}.contains(symbolCode.toUpperCase()))
                                                      Container(
                                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                        decoration: BoxDecoration(
                                                          color: Colors.orange.withOpacity(0.18),
                                                          borderRadius: BorderRadius.circular(3),
                                                          border: Border.all(color: Colors.orange.withOpacity(0.5)),
                                                        ),
                                                        child: const Text(
                                                          '⚠ Not for < \$20',
                                                          style: TextStyle(fontSize: 9, color: Colors.orange, fontWeight: FontWeight.w700),
                                                        ),
                                                      ),
                                                    // Micro-safe badge for recommended low-price symbols
                                                    if (isBinanceSymbol &&
                                                        const {'XRPUSDT', 'ADAUSDT', 'DOGEUSDT', 'TRXUSDT', 'XLMUSDT', 'HBARUSDT', 'MATICUSDT', 'SHIBUSDT', 'PEPEUSDT', 'TONUSDT'}.contains(symbolCode.toUpperCase()))
                                                      Container(
                                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                        decoration: BoxDecoration(
                                                          color: Colors.green.withOpacity(0.14),
                                                          borderRadius: BorderRadius.circular(3),
                                                          border: Border.all(color: Colors.green.withOpacity(0.4)),
                                                        ),
                                                        child: const Text(
                                                          '⚡ Micro-safe',
                                                          style: TextStyle(fontSize: 9, color: Colors.green, fontWeight: FontWeight.w700),
                                                        ),
                                                      ),
                                                    Container(
                                                      padding: const EdgeInsets.symmetric(
                                                        horizontal: 6,
                                                        vertical: 2,
                                                      ),
                                                      decoration: BoxDecoration(
                                                        color: traditionalBucketColor.withOpacity(0.18),
                                                        borderRadius: BorderRadius.circular(3),
                                                        border: Border.all(
                                                          color: traditionalBucketColor.withOpacity(0.4),
                                                        ),
                                                      ),
                                                      child: Text(
                                                        traditionalBucket,
                                                        style: TextStyle(
                                                          fontSize: 9,
                                                          color: traditionalBucketColor,
                                                          fontWeight: FontWeight.w700,
                                                        ),
                                                      ),
                                                    ),
                                                    if (!isBinanceSymbol)
                                                      Container(
                                                        padding: const EdgeInsets.symmetric(
                                                          horizontal: 6,
                                                          vertical: 2,
                                                        ),
                                                        decoration: BoxDecoration(
                                                          color: tradeabilityColor.withOpacity(0.18),
                                                          borderRadius: BorderRadius.circular(3),
                                                          border: Border.all(
                                                            color: tradeabilityColor.withOpacity(0.45),
                                                          ),
                                                        ),
                                                        child: Text(
                                                          tradeabilityLabel,
                                                          style: TextStyle(
                                                            fontSize: 9,
                                                            color: tradeabilityColor,
                                                            fontWeight: FontWeight.w700,
                                                          ),
                                                        ),
                                                      ),
                                                    Container(
                                                      padding: const EdgeInsets.symmetric(
                                                        horizontal: 6,
                                                        vertical: 2,
                                                      ),
                                                      decoration: BoxDecoration(
                                                        color: volatility == 'Low risk' || volatility == 'Low'
                                                            ? Colors.blue.withOpacity(0.2)
                                                            : volatility == 'High risk' || volatility == 'High'
                                                                ? Colors.orange.withOpacity(0.2)
                                                                : Colors.grey.withOpacity(0.2),
                                                        borderRadius: BorderRadius.circular(3),
                                                      ),
                                                      child: Text(
                                                        volatility,
                                                        style: const TextStyle(fontSize: 9),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                                const SizedBox(height: 4),
                                                Text(
                                                  '💡 $recommendation',
                                                  maxLines: 2,
                                                  overflow: TextOverflow.ellipsis,
                                                  style: TextStyle(
                                                    fontSize: 10,
                                                    color: Colors.grey[300],
                                                    fontStyle: FontStyle.italic,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ],
                                    );
                                    } catch (_) {
                                      final fallbackSymbol =
                                          _filteredTradingSymbols[index];
                                      final fallbackCode =
                                          fallbackSymbol['symbol'] ??
                                          'Unknown symbol';
                                      return Container(
                                        margin: const EdgeInsets.only(bottom: 8),
                                        decoration: BoxDecoration(
                                          border: Border.all(
                                            color: Colors.orangeAccent,
                                          ),
                                          borderRadius:
                                              BorderRadius.circular(8),
                                          color: Colors.orangeAccent
                                              .withOpacity(0.08),
                                        ),
                                        child: ListTile(
                                          title: Text(
                                            fallbackSymbol['name'] ?? fallbackCode,
                                          ),
                                          subtitle: Text(
                                            fallbackSymbol['category'] ?? 'General',
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      );
                                    }
                                  },
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Volatility Filter Toggle
                    SwitchListTile(
                      value: _volatilityFilterEnabled,
                      onChanged: (val) {
                        setState(() => _volatilityFilterEnabled = val);
                      },
                      title: const Text('Enable Volatility Filter'),
                      subtitle: const Text(
                        'If disabled, bot will trade regardless of market volatility.',
                      ),
                      contentPadding: EdgeInsets.zero,
                    ),
                    const SizedBox(height: 12),

                    // Intelligent Scanner Toggle
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: _intelligentScanner
                              ? [
                                  Colors.purple.withOpacity(0.2),
                                  Colors.blue.withOpacity(0.2),
                                ]
                              : [
                                  Colors.grey.withOpacity(0.1),
                                  Colors.grey.withOpacity(0.1),
                                ],
                        ),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _intelligentScanner
                              ? Colors.purpleAccent
                              : Colors.grey.withOpacity(0.3),
                        ),
                      ),
                      child: SwitchListTile(
                        value: _intelligentScanner,
                        onChanged: (val) {
                          setState(() => _intelligentScanner = val);
                        },
                        title: Row(
                          children: [
                            Icon(
                              Icons.psychology,
                              color: _intelligentScanner
                                  ? Colors.purpleAccent
                                  : Colors.grey,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            const Text('Auto Intelligent Scanner'),
                          ],
                        ),
                        subtitle: Text(
                          _intelligentScanner
                              ? 'ON — Bot scans the wider market every cycle, closes weak trades, reallocates to stronger opportunities, and stays enabled automatically for presets and advanced automation.'
                              : 'OFF — Bot only trades its assigned symbols unless advanced automation requires scanner support.',
                          style: TextStyle(
                            color: _intelligentScanner
                                ? Colors.purpleAccent.withOpacity(0.8)
                                : Colors.grey,
                            fontSize: 12,
                          ),
                        ),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Top-Movers Scanner Toggle
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: _topMoversEnabled
                              ? [
                                  Colors.orange.withOpacity(0.15),
                                  Colors.amber.withOpacity(0.10),
                                ]
                              : [
                                  Colors.grey.withOpacity(0.1),
                                  Colors.grey.withOpacity(0.1),
                                ],
                        ),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _topMoversEnabled
                              ? Colors.orange.withOpacity(0.6)
                              : Colors.grey.withOpacity(0.3),
                        ),
                      ),
                      child: SwitchListTile(
                        value: _topMoversEnabled,
                        onChanged: (val) {
                          setState(() => _topMoversEnabled = val);
                        },
                        title: Row(
                          children: [
                            Icon(
                              Icons.trending_up,
                              color: _topMoversEnabled
                                  ? Colors.orange
                                  : Colors.grey,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            const Text('Top Movers Scanner'),
                          ],
                        ),
                        subtitle: Text(
                          _topMoversEnabled
                              ? (_isExnessBroker
                                  ? 'ON — Bot tracks the top-moving crypto assets (e.g. BTC, ETH, SOL) every 2 minutes via Binance momentum data and maps them to your Exness CFDs (e.g. BTCUSDm), following new pumps and drops as they happen.'
                                  : 'ON — Bot automatically tracks the top-performing USDT pairs every 2 minutes and adds them to the scan universe, following new pumps and drops as they happen.')
                              : 'OFF — Bot only scans the symbols you configured above.',
                          style: TextStyle(
                            color: _topMoversEnabled
                                ? Colors.orange.withOpacity(0.8)
                                : Colors.grey,
                            fontSize: 12,
                          ),
                        ),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Top-Movers Direct Trading Toggle
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: _topMoversDirectTrading
                              ? [
                                  Colors.deepOrange.withOpacity(0.15),
                                  Colors.orange.withOpacity(0.08),
                                ]
                              : [
                                  Colors.grey.withOpacity(0.1),
                                  Colors.grey.withOpacity(0.1),
                                ],
                        ),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _topMoversDirectTrading
                              ? Colors.deepOrange.withOpacity(0.6)
                              : Colors.grey.withOpacity(0.3),
                        ),
                      ),
                      child: SwitchListTile(
                        value: _topMoversDirectTrading,
                        onChanged: (val) {
                          setState(() => _topMoversDirectTrading = val);
                        },
                        title: Row(
                          children: [
                            Icon(
                              Icons.bolt,
                              color: _topMoversDirectTrading
                                  ? Colors.deepOrange
                                  : Colors.grey,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            const Text('Top Movers Direct Trading'),
                          ],
                        ),
                        subtitle: Text(
                          _topMoversDirectTrading
                              ? (_isExnessBroker
                                  ? 'ON — Bot executes momentum trades directly on your Exness CFDs (e.g. BTCUSDm) when a top-moving crypto asset is detected, bypassing the signal engine. Requires Top Movers Scanner.'
                                  : 'ON — Bot executes momentum trades directly when a top mover is detected, bypassing the signal engine. Requires Top Movers Scanner.')
                              : 'OFF — Top movers are only added to the scan list; the signal engine decides entries.',
                          style: TextStyle(
                            color: _topMoversDirectTrading
                                ? Colors.deepOrange.withOpacity(0.8)
                                : Colors.grey,
                            fontSize: 12,
                          ),
                        ),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Currency Selection
                    Builder(
                      builder: (context) {
                        final activeCurrencyCode = _activeAccountCurrencyCode(
                          context,
                        );
                        final currencyLocked = _hasLinkedAccountCurrency;
                        return Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.blue.withOpacity(0.1),
                            border: Border.all(
                              color: Colors.blue.withOpacity(0.5),
                            ),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                currencyLocked
                                    ? 'Broker Account Currency'
                                    : 'Preset Currency Preview',
                                style: Theme.of(context).textTheme.titleSmall
                                    ?.copyWith(
                                      color: Colors.blue[200],
                                      fontWeight: FontWeight.bold,
                                    ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                currencyLocked
                                    ? 'Preset labels follow the linked broker account currency automatically.'
                                    : 'No broker account currency is locked yet, so preset labels follow this preview selection.',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey[400],
                                ),
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Expanded(
                                    child: ChoiceChip(
                                      label: const Text(r'$ USD'),
                                      selected: activeCurrencyCode == 'USD',
                                      onSelected: currencyLocked
                                          ? null
                                          : (_) => setState(
                                                () => _currencyChoice = 'USD',
                                              ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: ChoiceChip(
                                      label: const Text('R ZAR (Rand)'),
                                      selected: activeCurrencyCode == 'ZAR',
                                      onSelected: currencyLocked
                                          ? null
                                          : (_) => setState(
                                                () => _currencyChoice = 'ZAR',
                                              ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 16),

                    // Settings Mode Selection
                    const SizedBox(height: 16),

                    // ========== AUTOMATED RISK MANAGEMENT SETTINGS ==========
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: Colors.green.withOpacity(0.5),
                        ),
                        borderRadius: BorderRadius.circular(12),
                        color: Colors.green.withOpacity(0.05),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.security,
                                color: Colors.green,
                                size: 24,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Automated Risk Management',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium
                                          ?.copyWith(
                                            color: Colors.green,
                                            fontWeight: FontWeight.bold,
                                          ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Bot automatically calculates lot sizes, SL/TP levels, and enforces trading limits',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey[400],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),

                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '🧠 Assisted Management Profile',
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  ChoiceChip(
                                    label: const Text('Beginner'),
                                    selected: _managementProfile == 'beginner',
                                    onSelected: (_) =>
                                        _applyManagementProfile('beginner'),
                                  ),
                                  ChoiceChip(
                                    label: const Text('Balanced'),
                                    selected: _managementProfile == 'balanced',
                                    onSelected: (_) =>
                                        _applyManagementProfile('balanced'),
                                  ),
                                  ChoiceChip(
                                    label: const Text('Advanced'),
                                    selected: _managementProfile == 'advanced',
                                    onSelected: (_) =>
                                        _applyManagementProfile('advanced'),
                                  ),
                                  ChoiceChip(
                                    label: const Text('Quick Profit'),
                                    selected:
                                        _managementProfile == 'fast_growth',
                                    onSelected: (_) =>
                                        _applyManagementProfile('fast_growth'),
                                    backgroundColor: Colors.orange.withOpacity(
                                      0.15,
                                    ),
                                    labelStyle: const TextStyle(
                                      color: Colors.orange,
                                    ),
                                  ),
                                  if (_selectedPreset != null)
                                    ChoiceChip(
                                      label: const Text('Small Account'),
                                      selected:
                                          _managementProfile == 'small_account',
                                      onSelected: (_) =>
                                          _applyManagementProfile(
                                            'small_account',
                                          ),
                                      backgroundColor: Colors.amber.withOpacity(
                                        0.15,
                                      ),
                                      labelStyle: const TextStyle(
                                        color: Colors.amber,
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Builder(
                                builder: (context) {
                                  final currencyCode =
                                      _activeAccountCurrencyCode(context);
                                  final selectedPreset = _selectedPreset == null
                                      ? null
                                      : _smallAccountPresets[_selectedPreset!];
                                  final smallAccountRange = _formatPresetRange(
                                    ((selectedPreset?['recommendedMinUsd']
                                                    as num?)
                                                ?.toDouble() ??
                                            10.0),
                                    ((selectedPreset?['recommendedMaxUsd']
                                                    as num?)
                                                ?.toDouble() ??
                                            1000.0),
                                    currencyCode,
                                  );
                                  return Text(
                                    _managementProfile == 'beginner'
                                        ? 'Recommended for inexperienced clients: fewer trades, stricter signals, and low-volatility execution only.'
                                        : _managementProfile == 'balanced'
                                        ? 'Moderate automation: controlled stacking with medium-volatility access.'
                                        : _managementProfile == 'fast_growth'
                                        ? 'Quick Profit: Faster entries with stricter signal quality, tighter drawdown limits, and stronger profit lock behavior.'
                                        : _managementProfile == 'small_account'
                                        ? 'Small Account: Optimized for $smallAccountRange. Micro lots, swing entries, and controlled volatility in ${_currencyUnitName(currencyCode)}.'
                                        : 'Keeps intelligent protections on while allowing broader execution settings.',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey[400],
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),

                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Signal Threshold',
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                _isCryptoOnlySelection
                                    ? 'Crypto-only baskets default to 5 so Binance bots can act on low-strength qualifying signals.'
                                    : 'Auto lets the backend choose the threshold from the profile and adaptive logic. Pick a value only when you want to force the minimum signal strength.',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey[400],
                                ),
                              ),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  ChoiceChip(
                                    label: Text(_signalThresholdLabel()),
                                    selected: _manualSignalThreshold == null,
                                    onSelected: (_) => setState(
                                      () => _manualSignalThreshold = null,
                                    ),
                                  ),
                                  for (final threshold in _availableSignalThresholds)
                                    ChoiceChip(
                                      label: Text('$threshold'),
                                      selected:
                                          _manualSignalThreshold == threshold,
                                      onSelected: (_) => setState(() {
                                        _manualSignalThreshold = threshold;
                                        _applyCryptoSelectionSafetyDefaults();
                                      }),
                                    ),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),

                          // Trade Amount Input
                          Builder(
                            builder: (context) {
                              final currLabel = _activeAccountCurrencyCode(
                                context,
                              );
                              final prefix = _currencyPrefixForCode(currLabel);
                              final selectedTradeAmount = double.tryParse(
                                _investmentAmountController.text.trim(),
                              );
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '💵 Trade Amount ($currLabel)',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(fontWeight: FontWeight.bold),
                                  ),
                                  const SizedBox(height: 8),
                                  TextField(
                                    controller: _investmentAmountController,
                                    onChanged: (_) => setState(() {}),
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                          decimal: true,
                                        ),
                                    decoration: InputDecoration(
                                      hintText:
                                          'Optional fixed amount per trade in $currLabel',
                                      prefixText: prefix,
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      filled: true,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'This follows the selected broker account currency. Demo USD accounts use dollars, live ZAR accounts use rands. Leave it empty to size trades from Risk % instead.',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey[400],
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: [
                                      for (final amount in _tradeAmountPresets)
                                        ChoiceChip(
                                          label: Text(
                                            _formatPresetTradeAmount(
                                              amount,
                                              currLabel,
                                            ),
                                          ),
                                          selected:
                                              selectedTradeAmount != null &&
                                              (selectedTradeAmount - amount)
                                                      .abs() <
                                                  0.0001,
                                          onSelected: (_) =>
                                              _applyTradeAmountPreset(amount),
                                        ),
                                      ActionChip(
                                        label: const Text('Clear'),
                                        onPressed: () {
                                          _investmentAmountController.clear();
                                          setState(() {});
                                        },
                                      ),
                                    ],
                                  ),
                                  if (_fixedTradeAmountWarningData(context)
                                      case final warning?) ...[
                                    const SizedBox(height: 8),
                                    Container(
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: Colors.orange.withOpacity(0.10),
                                        border: Border.all(
                                          color: Colors.orange.withOpacity(
                                            0.45,
                                          ),
                                        ),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          const Icon(
                                            Icons.warning_amber_rounded,
                                            color: Colors.orange,
                                            size: 18,
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              'Entered amount looks low for ${warning['symbols']}. Estimated minimum is about '
                                              '${(warning['minimum'] as double).toStringAsFixed(2)} ${warning['currency']}.',
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: Colors.grey[300],
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ],
                              );
                            },
                          ),
                          const SizedBox(height: 16),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    '💰 Risk Per Trade',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(fontWeight: FontWeight.bold),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.green.withOpacity(0.2),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      '${_riskPercent.toStringAsFixed(2)}%',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: Colors.green,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Slider(
                                value: _riskPercent,
                                min: 0.1,
                                max: 10,
                                divisions: 99,
                                onChanged: (value) =>
                                    setState(() => _riskPercent = value),
                                label: '${_riskPercent.toStringAsFixed(2)}%',
                              ),
                              Text(
                                'Amount risked per trade relative to account balance. Conservative: 1-2%, Moderate: 2-3%, Aggressive: 3-5%',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey[400],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),

                          // Max Open Trades Slider
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    '📊 Max Open Trades',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(fontWeight: FontWeight.bold),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.blue.withOpacity(0.2),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      '$_maxOpenTrades trades',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: Colors.blue,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Slider(
                                value: _maxOpenTrades.toDouble(),
                                min: 1,
                                max: 20,
                                divisions: 19,
                                onChanged: (value) => setState(
                                  () => _maxOpenTrades = value.toInt(),
                                ),
                                label: '$_maxOpenTrades',
                              ),
                              Text(
                                'Limits total simultaneous positions. Lower = less risk, Higher = more diversification. Recommended: 2-3',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey[400],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),

                          // Max Drawdown Slider
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    '📉 Max Drawdown',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(fontWeight: FontWeight.bold),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.purple.withOpacity(0.2),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      '${_maxDrawdownPercent.toStringAsFixed(1)}%',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: Colors.purple,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Slider(
                                value: _maxDrawdownPercent,
                                min: 5,
                                max: 50,
                                divisions: 45,
                                onChanged: (value) =>
                                    setState(() => _maxDrawdownPercent = value),
                                label:
                                    '${_maxDrawdownPercent.toStringAsFixed(1)}%',
                              ),
                              Text(
                                'Trading pauses when account loses this %. Allows system recovery before resuming. Recommended: 15-20%',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey[400],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.blue.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: Colors.blue.withOpacity(0.3),
                              ),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.info,
                                  color: Colors.blue,
                                  size: 18,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    'These settings are used for automatic lot sizing. No manual position entry needed!',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.blue[200],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.orange.withOpacity(0.5)),
                        borderRadius: BorderRadius.circular(8),
                        color: Colors.orange.withOpacity(0.05),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.copy_all_outlined,
                                color: Colors.orange,
                                size: 24,
                              ),
                              const SizedBox(width: 12),
                              Text(
                                'Copy Trading',
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(color: Colors.orange),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          SwitchListTile(
                            value: _copyTradingEnabled,
                            onChanged: (value) {
                              setState(() {
                                _copyTradingEnabled = value;
                                if (value) {
                                  _copyTradingSourceMode = 'auto_success';
                                  _copyTradingSourceBotId = null;
                                  _copyTradingSourceFeedback = null;
                                } else {
                                  _copyTradingSources = [];
                                  _copyTradingResolvedSourceBotId = null;
                                  _copyTradingSourceFeedback = null;
                                }
                              });
                              if (value) {
                                unawaited(_loadCopyTradingSources());
                              }
                            },
                            title: const Text('Mirror Successful Traders Automatically'),
                            subtitle: Text(
                              _copyTradingEnabled
                                  ? 'This bot will stop placing its own entries and will follow the highest-performing active ${_brokerService.activeCredential?.broker ?? 'broker'} bot on the same broker and mode.'
                                  : 'Enable follower mode so this bot mirrors real fills from the best-performing active bot on the same broker and mode.',
                              style: const TextStyle(fontSize: 12),
                            ),
                            contentPadding: EdgeInsets.zero,
                          ),
                          if (_copyTradingEnabled)
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                DropdownButtonFormField<String>(
                                  value: _copyTradingSourceMode,
                                  decoration: InputDecoration(
                                    labelText: 'Source Mode',
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                  ),
                                  items: const [
                                    DropdownMenuItem(
                                      value: 'auto_success',
                                      child: Text('Auto select best successful bot'),
                                    ),
                                    DropdownMenuItem(
                                      value: 'manual',
                                      child: Text('Choose source bot manually'),
                                    ),
                                  ],
                                  onChanged: (value) {
                                    if (value == null) {
                                      return;
                                    }
                                    setState(() {
                                      _copyTradingSourceMode = value;
                                      if (value != 'manual') {
                                        _copyTradingSourceBotId = null;
                                      }
                                      _copyTradingSourceFeedback = null;
                                    });
                                    unawaited(_loadCopyTradingSources());
                                  },
                                ),
                                const SizedBox(height: 12),
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Colors.orange.withOpacity(0.08),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    _copyTradingSourceMode == 'manual'
                                        ? 'Choose exactly which active ${_brokerService.activeCredential?.broker ?? 'broker'} bot this follower should mirror. Only same-broker, same-mode leaders qualify.'
                                        : 'Auto mode picks the top profitable active bot with at least 3 trades and 1 win. Your follower bot still uses its own broker credentials and risk sizing.',
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                ),
                                if (_copyTradingSourceMode == 'manual') ...[
                                  const SizedBox(height: 12),
                                  if (_isLoadingCopyTradingSources)
                                    const Center(child: CircularProgressIndicator())
                                  else if (_copyTradingSources.isEmpty)
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            'No eligible ${_brokerService.activeCredential?.broker ?? 'broker'} source bots are available yet. Refresh after running at least one bot.',
                                            style: const TextStyle(fontSize: 12),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        OutlinedButton.icon(
                                          onPressed: _loadCopyTradingSources,
                                          icon: const Icon(Icons.refresh, size: 18),
                                          label: const Text('Refresh'),
                                        ),
                                      ],
                                    )
                                  else
                                    DropdownButtonFormField<String>(
                                      value: (_copyTradingSourceBotId ?? '').trim().isEmpty
                                          ? null
                                          : _copyTradingSourceBotId,
                                      decoration: InputDecoration(
                                        labelText: 'Source Bot',
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                      ),
                                        items: _copyTradingSources
                                          .map(
                                            (template) => DropdownMenuItem<String>(
                                              value: (template['sourceBotId'] ?? '').toString().trim(),
                                              child: Text(
                                                _copyTradingSourceTemplateLabel(template),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          )
                                          .toList(),
                                      onChanged: (value) {
                                        setState(() {
                                          _copyTradingSourceBotId = value?.trim().isEmpty ?? true
                                              ? null
                                              : value!.trim();
                                        });
                                        unawaited(_loadCopyTradingSources());
                                      },
                                    ),
                                  if ((_copyTradingSourceFeedback ?? '').trim().isNotEmpty) ...[
                                    const SizedBox(height: 10),
                                    Text(
                                      _copyTradingSourceFeedback!,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.orange[200],
                                      ),
                                    ),
                                  ],
                                ],
                                if (_copyTradingSourceMode != 'manual' && (_copyTradingSourceFeedback ?? '').trim().isNotEmpty) ...[
                                  const SizedBox(height: 10),
                                  Text(
                                    _copyTradingSourceFeedback!,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.orange[200],
                                    ),
                                  ),
                                ],
                              ],
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Profit Protection Settings
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.teal.withOpacity(0.5)),
                        borderRadius: BorderRadius.circular(8),
                        color: Colors.teal.withOpacity(0.05),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.shield_outlined,
                                color: Colors.teal,
                                size: 24,
                              ),
                              const SizedBox(width: 12),
                              Text(
                                'Profit Protection',
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(color: Colors.teal),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          SwitchListTile(
                            value: _enableProfitProtection,
                            onChanged: (value) {
                              setState(() => _enableProfitProtection = value);
                            },
                            title: const Text('Lock Winner Profits'),
                            subtitle: const Text(
                              'Arm a floor once a trade reaches profit, then close it on retrace or signal reversal. The backend also locks break-even plus costs after a good move.',
                              style: TextStyle(fontSize: 12),
                            ),
                            contentPadding: EdgeInsets.zero,
                          ),
                          if (_enableProfitProtection) ...[
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    keyboardType: TextInputType.number,
                                    decoration: InputDecoration(
                                      labelText: 'Arm At Profit %',
                                      hintText: '5',
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                    ),
                                    onChanged: (value) {
                                      setState(() {
                                        _profitProtectionActivationPercent =
                                            double.tryParse(value) ?? 5;
                                      });
                                    },
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: TextField(
                                    keyboardType: TextInputType.number,
                                    decoration: InputDecoration(
                                      labelText: 'Arm At Min Profit',
                                      hintText: '5',
                                      helperText:
                                          'Protection only arms after this profit amount is reached.',
                                      helperMaxLines: 2,
                                      alignLabelWithHint: true,
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                    ),
                                    onChanged: (value) {
                                      setState(() {
                                        _profitProtectionActivationMinProfit =
                                            double.tryParse(value) ?? 5;
                                      });
                                    },
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              keyboardType: TextInputType.number,
                              decoration: InputDecoration(
                                labelText: 'Guaranteed Profit Floor',
                                hintText: '8',
                                helperText:
                                    'Once armed, do not let a winner give back below this profit floor before the retrace rules are applied.',
                                helperMaxLines: 2,
                                alignLabelWithHint: true,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(6),
                                ),
                              ),
                              onChanged: (value) {
                                setState(() {
                                  _profitProtectionMinLockedProfit =
                                      double.tryParse(value) ?? 0;
                                });
                              },
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              keyboardType: TextInputType.number,
                              decoration: InputDecoration(
                                labelText: 'Take Profit At Margin %',
                                hintText: '30',
                                helperText:
                                    'Hard close the trade once profit reaches this percentage of the trade margin. Use 30 to bank spike trades immediately.',
                                helperMaxLines: 2,
                                alignLabelWithHint: true,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(6),
                                ),
                              ),
                              onChanged: (value) {
                                setState(() {
                                  _profitProtectionMarginTakeProfitPercent =
                                      double.tryParse(value) ?? 30;
                                });
                              },
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              keyboardType: TextInputType.number,
                              decoration: InputDecoration(
                                labelText: 'Max Profit Giveback Cap %',
                                hintText: '35',
                                helperText:
                                    'The backend auto-tightens this by instrument volatility and also applies a break-even-plus-costs floor after a strong move. Lower-vol forex may lock near 18-22%, while crypto/high-vol stocks may allow up to about 30-35%.',
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(6),
                                ),
                              ),
                              onChanged: (value) {
                                setState(() {
                                  _profitProtectionRetracePercent =
                                      double.tryParse(value) ?? 35;
                                });
                              },
                            ),
                            SwitchListTile(
                              value: _profitProtectionAdaptiveByVolatility,
                              onChanged: (value) {
                                setState(
                                  () =>
                                      _profitProtectionAdaptiveByVolatility =
                                          value,
                                );
                              },
                              title: const Text('Auto Adjust For Volatility'),
                              subtitle: const Text(
                                'Keep this on to let the backend raise activation and floor settings for higher-volatility symbols like BTC/ETH. Turn it off to use your exact profit-lock values.',
                                style: TextStyle(fontSize: 12),
                              ),
                              contentPadding: EdgeInsets.zero,
                            ),
                            SwitchListTile(
                              value: _profitProtectionSwitchOnReversal,
                              onChanged: (value) {
                                setState(
                                  () =>
                                      _profitProtectionSwitchOnReversal = value,
                                );
                              },
                              title: const Text('Close On Signal Reversal'),
                              subtitle: const Text(
                                'If the winner flips direction, close it and let the auto scanner look for a stronger pair.',
                                style: TextStyle(fontSize: 12),
                              ),
                              contentPadding: EdgeInsets.zero,
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Create Bot Button
            Center(
              child: Column(
                children: [
                  if (_isEditMode) ...[
                    OutlinedButton.icon(
                      onPressed: (_isCreating || _isLoadingExistingBot)
                          ? null
                          : () => _createAndStartBot(restartAfterSave: true),
                      icon: _isCreating
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.refresh),
                      label: Text(
                        _isCreating
                            ? 'Saving & Restarting...'
                            : 'Save & Restart Bot',
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF00E5FF),
                        side: const BorderSide(color: Color(0xFF00E5FF)),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 28,
                          vertical: 14,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  ElevatedButton.icon(
                    onPressed: (_isCreating || _isLoadingExistingBot)
                        ? null
                        : _createAndStartBot,
                    icon: _isCreating
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.add_circle),
                    label: Text(
                      _isCreating
                          ? (_isEditMode
                                ? 'Saving Bot Changes...'
                                : 'Creating & Starting Bot...')
                          : (_isEditMode
                                ? 'Save Bot Changes'
                                : (_isCloneMode
                                      ? (widget.promoteToLive
                                            ? 'Promote To Live Bot'
                                            : 'Create Cloned Bot')
                                      : 'Create & Start Bot')),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 32,
                        vertical: 16,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        backgroundColor: const Color(0xFF111633),
        selectedItemColor: const Color(0xFF00E5FF),
        unselectedItemColor: Colors.white38,
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.dashboard_rounded),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.smart_toy_outlined),
            label: 'Bots',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.assessment_rounded),
            label: 'Reports',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.tune_rounded),
            label: 'Config',
          ),
        ],
        currentIndex: 3,
        onTap: (index) {
          if (index == 0) {
            Navigator.of(context).popUntil((route) => route.isFirst);
          } else if (index == 1) {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) => const BotDashboardScreen(),
              ),
            );
          } else if (index == 2) {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) => const ConsolidatedReportsScreen(),
              ),
            );
          }
        },
      ),
    );
  }

  void _triggerFundTransfer(
    String fromAccount,
    String toAccount,
    double amount,
  ) async {
    final success = await _fundService.transferFunds(
      fromAccount,
      toAccount,
      amount,
    );
    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Funds transferred successfully!')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_fundService.errorMessage ?? 'Transfer failed')),
      );
    }
  }
}

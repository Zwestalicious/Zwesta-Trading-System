import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/trade.dart';
import '../services/financial_export_service.dart';
import '../theme/app_design.dart';
import '../services/trading_service.dart';
import '../utils/constants.dart';
import '../utils/environment_config.dart';
import '../widgets/custom_widgets.dart';
import 'broker_integration_screen.dart';

class TradesScreen extends StatefulWidget {
  const TradesScreen({Key? key}) : super(key: key);

  @override
  State<TradesScreen> createState() => _TradesScreenState();
}

class _TradesScreenState extends State<TradesScreen> {
  int _selectedTab = 0; // 0: all, 1: open, 2: closed

  @override
  Widget build(BuildContext context) => Scaffold(
        extendBodyBehindAppBar: true,
        appBar: CustomAppBar(
          title: 'Trades',
          showBackButton: true,
          showLogo: false,
          actions: [
            IconButton(
              icon: const Icon(Icons.add),
              onPressed: () => _showOpenTradeDialog(context),
            ),
            PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'export_pdf') {
                  _exportTradesPdf(context);
                } else if (value == 'share_report') {
                  _shareTradesReport(context);
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'export_pdf',
                  child: Row(
                    children: [
                      const Icon(Icons.picture_as_pdf_outlined,
                          color: Color(0xFF4CAF50), size: 18),
                      const SizedBox(width: 8),
                      Text('Export PDF',
                          style: GoogleFonts.poppins(
                              color: const Color(0xFF4CAF50), fontSize: 13)),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'share_report',
                  child: Row(
                    children: [
                      const Icon(Icons.share_outlined,
                          color: Color(0xFF00E5FF), size: 18),
                      const SizedBox(width: 8),
                      Text('Share Report',
                          style: GoogleFonts.poppins(
                              color: const Color(0xFF00E5FF), fontSize: 13)),
                    ],
                  ),
                ),
              ],
              icon: const Icon(Icons.more_vert),
            ),
          ],
        ),
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF0A0E21), Color(0xFF1A237E), Color(0xFF512DA8)],
            ),
          ),
          child: _buildTradesContent(),
        ),
      );

  Widget _buildTradesContent() => Consumer<TradingService>(
        builder: (context, tradingService, _) => SafeArea(
          child: Column(
            children: [
              // Connected broker banner
              FutureBuilder<SharedPreferences>(
                future: SharedPreferences.getInstance(),
                builder: (ctx, snap) {
                  if (!snap.hasData) return const SizedBox.shrink();
                  final prefs = snap.data!;
                  final broker = prefs.getString('broker');
                  final connected = prefs.getBool('broker_connected') == true;
                  return GestureDetector(
                    onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const BrokerIntegrationScreen())),
                    child: Container(
                      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: connected
                            ? Colors.green.withOpacity(0.1)
                            : Colors.orange.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: connected
                                ? Colors.green.withOpacity(0.3)
                                : Colors.orange.withOpacity(0.3)),
                      ),
                      child: Row(
                        children: [
                          Icon(connected ? Icons.link : Icons.link_off,
                              color: connected ? Colors.green : Colors.orange,
                              size: 18),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              connected
                                  ? 'Connected to ${broker ?? "Broker"}'
                                  : 'No broker connected',
                              style: GoogleFonts.poppins(
                                  color:
                                      connected ? Colors.green : Colors.orange,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500),
                            ),
                          ),
                          Text('Manage',
                              style: GoogleFonts.poppins(
                                  color: AppColors.primaryColor,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600)),
                          const SizedBox(width: 4),
                          const Icon(Icons.chevron_right,
                              color: AppColors.primaryColor, size: 16),
                        ],
                      ),
                    ),
                  );
                },
              ),

              // Live Positions Indicator
              Container(
                margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF00E5FF).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: const Color(0xFF00E5FF).withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Color(0xFF00E5FF),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Live MT5 positions • Auto-refreshing every 30 seconds',
                        style: GoogleFonts.poppins(
                          color: const Color(0xFF00E5FF),
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const Icon(Icons.update,
                        color: Color(0xFF00E5FF), size: 16),
                  ],
                ),
              ),

              // Account Balance Card
              Container(
                margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      const Color(0xFF1A237E).withOpacity(0.5),
                      const Color(0xFF0D47A1).withOpacity(0.3),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: const Color(0xFF00E5FF).withOpacity(0.2)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildAccountMetric('Account Balance',
                        tradingService.accountBalance, Colors.white, tradingService.accountCurrencySymbol),
                    Container(
                        width: 1,
                        height: 40,
                        color: Colors.white.withOpacity(0.1)),
                    _buildAccountMetric('Equity', tradingService.accountEquity,
                        const Color(0xFF4CAF50), tradingService.accountCurrencySymbol),
                    Container(
                        width: 1,
                        height: 40,
                        color: Colors.white.withOpacity(0.1)),
                    _buildAccountMetric('Free Margin',
                        tradingService.freeMargin, const Color(0xFF00E5FF), tradingService.accountCurrencySymbol),
                  ],
                ),
              ),

              // Tab Selector
              Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Row(
                  children: [
                    _buildTabButton(
                      context,
                      'All',
                      0,
                      '${tradingService.trades.length}',
                    ),
                    const SizedBox(width: AppSpacing.md),
                    _buildTabButton(
                      context,
                      'Open',
                      1,
                      '${tradingService.activeTrades.length}',
                    ),
                    const SizedBox(width: AppSpacing.md),
                    _buildTabButton(
                      context,
                      'Closed',
                      2,
                      '${tradingService.closedTrades.length}',
                    ),
                    const SizedBox(width: AppSpacing.md),
                    _buildTabButton(
                      context,
                      'Live MT5',
                      3,
                      '${tradingService.liveOpenPositions.length}',
                    ),
                  ],
                ),
              ),

              // Trades List
              Expanded(
                child: RefreshIndicator(
                  onRefresh: () async {
                    await tradingService.fetchTrades();
                  },
                  child: _buildTradesList(context, tradingService),
                ),
              ),
            ],
          ),
        ),
      );

  Widget _buildAccountMetric(String label, double value, Color color, String currencySymbol) => Column(
        children: [
          Text(
            label,
            style: GoogleFonts.poppins(color: Colors.white60, fontSize: 10),
          ),
          const SizedBox(height: 4),
          Text(
            '$currencySymbol${value.toStringAsFixed(2)}',
            style: GoogleFonts.poppins(
              color: color,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      );

  Widget _buildLivePositionCard(BuildContext context, Trade position) {
    final symbol = position.symbol;
    final type = position.type == TradeType.buy ? 'BUY' : 'SELL';
    final volume = position.quantity;
    final openPrice = position.entryPrice;
    final currentPrice = position.currentPrice ?? position.entryPrice;
    final profit = position.profit ?? 0.0;
    final profitPct =
        openPrice > 0 ? ((currentPrice - openPrice) / openPrice * 100) : 0.0;
    final openTime = position.openedAt.toString().split('.')[0];

    final isBuy = position.type == TradeType.buy;
    final isProfitable = profit >= 0;
    // Derive currency prefix from the trade's currency field
    final currencyCode = position.currency.toUpperCase();
    final currencyPrefix = currencyCode == 'ZAR' ? 'R'
        : currencyCode == 'USD' ? r'$'
        : currencyCode == 'EUR' ? '\u20AC'
        : currencyCode == 'GBP' ? '\u00A3'
        : '$currencyCode ';
    // Prices for Binance USDT pairs are in USD; no R prefix needed
    final pricePrefix = currencyCode == 'ZAR' ? 'R' : '';
    final priceSuffix = currencyCode != 'ZAR' && currencyCode != 'USD' && currencyCode != 'EUR' && currencyCode != 'GBP' ? ' $currencyCode' : '';

    return Card(
      color: Colors.white.withOpacity(0.05),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isProfitable
                ? const Color(0xFF4CAF50).withOpacity(0.3)
                : const Color(0xFFFF5252).withOpacity(0.3),
          ),
        ),
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF00E5FF).withOpacity(0.2),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                        color: const Color(0xFF00E5FF).withOpacity(0.4)),
                  ),
                  child: Text(
                    'LIVE',
                    style: GoogleFonts.poppins(
                      color: const Color(0xFF00E5FF),
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    symbol,
                    style: GoogleFonts.poppins(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: isBuy
                        ? const Color(0xFF1B5E20).withOpacity(0.2)
                        : const Color(0xFFB71C1C).withOpacity(0.2),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    type,
                    style: GoogleFonts.poppins(
                      color: isBuy
                          ? const Color(0xFF4CAF50)
                          : const Color(0xFFFF5252),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Volume',
                        style: GoogleFonts.poppins(
                            color: Colors.white60, fontSize: 10)),
                    Text('$volume lots',
                        style: GoogleFonts.poppins(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w500)),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('Open Price',
                        style: GoogleFonts.poppins(
                            color: Colors.white60, fontSize: 10)),
                    Text('$pricePrefix${openPrice.toStringAsFixed(5)}$priceSuffix',
                        style: GoogleFonts.poppins(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w500)),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('Current Price',
                        style: GoogleFonts.poppins(
                            color: Colors.white60, fontSize: 10)),
                    Text('$pricePrefix${currentPrice.toStringAsFixed(5)}$priceSuffix',
                        style: GoogleFonts.poppins(
                            color: const Color(0xFF00E5FF),
                            fontSize: 13,
                            fontWeight: FontWeight.w500)),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isProfitable
                    ? const Color(0xFF4CAF50).withOpacity(0.1)
                    : const Color(0xFFFF5252).withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isProfitable
                      ? const Color(0xFF4CAF50).withOpacity(0.3)
                      : const Color(0xFFFF5252).withOpacity(0.3),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(
                        isProfitable ? Icons.trending_up : Icons.trending_down,
                        color: isProfitable
                            ? const Color(0xFF4CAF50)
                            : const Color(0xFFFF5252),
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('P/L',
                              style: GoogleFonts.poppins(
                                  color: Colors.white60, fontSize: 10)),
                          Text(
                            '${isProfitable ? '+' : ''}$currencyPrefix${profit.toStringAsFixed(2)}',
                            style: GoogleFonts.poppins(
                              color: isProfitable
                                  ? const Color(0xFF4CAF50)
                                  : const Color(0xFFFF5252),
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  Text(
                    '${isProfitable ? '+' : ''}${profitPct.toStringAsFixed(2)}%',
                    style: GoogleFonts.poppins(
                      color: isProfitable
                          ? const Color(0xFF4CAF50)
                          : const Color(0xFFFF5252),
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            if (openTime.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'Opened: $openTime',
                style: GoogleFonts.poppins(color: Colors.white38, fontSize: 9),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTabButton(
      BuildContext context, String label, int index, String count) {
    final isSelected = _selectedTab == index;
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedTab = index;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primaryColor : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color:
                isSelected ? AppColors.primaryColor : AppColors.veryLightGrey,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: isSelected ? Colors.white : AppColors.darkGrey,
              ),
            ),
            Text(
              count,
              style: TextStyle(
                fontSize: 12,
                color: isSelected ? Colors.white70 : AppColors.grey,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTradesList(BuildContext context, TradingService tradingService) {
    // Handle Live MT5 Tab (case 3)
    if (_selectedTab == 3) {
      final livePositions = tradingService.liveOpenPositions;

      if (livePositions.isEmpty) {
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.cloud_off_outlined,
                size: 64,
                color: AppColors.lightGrey,
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                'No live MT5 positions',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Live positions from MT5 will appear here',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        );
      }

      return ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: livePositions.length,
        itemBuilder: (context, index) =>
            _buildLivePositionCard(context, livePositions[index]),
      );
    }

    // Regular Trades List for tabs 0, 1, 2
    List<Trade> trades;

    switch (_selectedTab) {
      case 1:
        trades = tradingService.activeTrades;
        break;
      case 2:
        trades = tradingService.closedTrades;
        break;
      default:
        trades = tradingService.trades;
    }

    if (trades.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.trending_up,
              size: 64,
              color: AppColors.lightGrey,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              _selectedTab == 1
                  ? 'No open trades'
                  : 'No ${_selectedTab == 2 ? 'closed' : ''} trades',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              _selectedTab == 1
                  ? 'Tap + to open a new trade'
                  : 'You haven\'t closed any trades yet',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(AppSpacing.md),
      itemCount: trades.length,
      itemBuilder: (context, index) {
        final trade = trades[index];
        final tc = trade.currency.toUpperCase();
        final tradeSymbol = tc == 'ZAR' ? 'R'
            : tc == 'USD' ? r'$'
            : tc == 'EUR' ? '\u20AC'
            : tc == 'GBP' ? '\u00A3'
            : '$tc ';
        return TradeCard(
          symbol: trade.symbol,
          type: trade.type.toString().split('.').last,
          quantity: trade.quantity,
          entryPrice: trade.entryPrice,
          currentPrice: trade.currentPrice ?? trade.entryPrice,
          profit: trade.profit ?? 0,
          profitPercentage: trade.profitPercentage ?? 0,
          currencySymbol: tradeSymbol,
          openedAt: trade.openedAt,
          closedAt: trade.closedAt,
          onTap: () {
            tradingService.selectTrade(trade);
            _showTradeDetailsDialog(context, trade, tradingService);
          },
        );
      },
    );
  }

  /// Fetch trading symbols from the backend API
  Future<List<Map<String, String>>> _fetchTradingSymbolsForDialog() async {
    try {
      final response = await http
          .get(
            Uri.parse('${EnvironmentConfig.apiUrl}/api/commodities/list'),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final commodities = data['commodities'] as Map;

        final symbols = <Map<String, String>>[];

        commodities.forEach((category, items) {
          if (items is List) {
            for (final item in items) {
              if (item is Map) {
                final symbol = item['symbol'] ?? '';
                final name = item['name'] ?? '';
                if (symbol.isNotEmpty && name.isNotEmpty) {
                  symbols.add({
                    'symbol': symbol,
                    'name': name,
                  });
                }
              }
            }
          }
        });

        return symbols;
      }
    } catch (e) {
      print('Error fetching trading symbols: $e');
    }

    // Fallback to minimal list if API fails
    return [
      {'symbol': 'EURUSD', 'name': 'EUR/USD'},
      {'symbol': 'GBPUSD', 'name': 'GBP/USD'},
      {'symbol': 'XPTUSD', 'name': 'Platinum'},
      {'symbol': 'XAUUSD', 'name': 'Gold (XAU/USD)'},
    ];
  }

  void _showOpenTradeDialog(BuildContext context) {
    final quantityController = TextEditingController();
    final entryPriceController = TextEditingController();
    final takeProfitController = TextEditingController();
    final stopLossController = TextEditingController();
    var selectedType = 'buy';
    var selectedSymbol = 'EURUSD';

    // Initialize with empty list, will be populated from API
    var tradingSymbols = <Map<String, String>>[];

    // Fetch trading symbols from backend API
    _fetchTradingSymbolsForDialog().then((symbols) {
      // This is used in the showDialog below
      tradingSymbols = symbols;
    });

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Open New Trade'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                value: selectedType,
                decoration: const InputDecoration(labelText: 'Trade Type'),
                items: const [
                  DropdownMenuItem(value: 'buy', child: Text('Buy')),
                  DropdownMenuItem(value: 'sell', child: Text('Sell')),
                ],
                onChanged: (value) {
                  selectedType = value ?? 'buy';
                },
              ),
              const SizedBox(height: AppSpacing.md),
              DropdownButtonFormField<String>(
                value: selectedSymbol,
                decoration:
                    const InputDecoration(labelText: 'Select Symbol/Commodity'),
                items: tradingSymbols
                    .map((item) => DropdownMenuItem(
                          value: item['symbol'],
                          child: Text(item['name'] ?? ''),
                        ))
                    .toList(),
                onChanged: (value) {
                  selectedSymbol = value ?? 'EURUSD';
                },
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: quantityController,
                decoration: const InputDecoration(labelText: 'Quantity'),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: entryPriceController,
                decoration: const InputDecoration(labelText: 'Entry Price'),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: takeProfitController,
                decoration:
                    const InputDecoration(labelText: 'Take Profit (Optional)'),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: stopLossController,
                decoration:
                    const InputDecoration(labelText: 'Stop Loss (Optional)'),
                keyboardType: TextInputType.number,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              _submitOpenTrade(
                context,
                selectedSymbol,
                selectedType,
                double.tryParse(quantityController.text) ?? 0,
                double.tryParse(entryPriceController.text) ?? 0,
                double.tryParse(takeProfitController.text),
                double.tryParse(stopLossController.text),
              );
            },
            child: const Text('Open Trade'),
          ),
        ],
      ),
    );
  }

  void _submitOpenTrade(
    BuildContext context,
    String symbol,
    String type,
    double quantity,
    double entryPrice,
    double? takeProfit,
    double? stopLoss,
  ) async {
    final tradingService = context.read<TradingService>();

    final success = await tradingService.openTrade(
      symbol,
      type == 'buy' ? TradeType.buy : TradeType.sell,
      quantity,
      entryPrice,
      takeProfit,
      stopLoss,
    );

    if (mounted) {
      Navigator.pop(context);
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Trade opened successfully')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content:
                  Text(tradingService.errorMessage ?? 'Error opening trade')),
        );
      }
    }
  }

  void _showTradeDetailsDialog(
      BuildContext context, Trade trade, TradingService tradingService) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${trade.symbol} Details'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildDetailRow('Symbol', trade.symbol),
              _buildDetailRow(
                  'Type', trade.type.toString().split('.').last.toUpperCase()),
              _buildDetailRow(
                  'Quantity', '${trade.quantity.toStringAsFixed(0)} units'),
              _buildDetailRow(
                  'Entry Price', trade.entryPrice.toStringAsFixed(4)),
              _buildDetailRow(
                'Current Price',
                (trade.currentPrice ?? trade.entryPrice).toStringAsFixed(4),
              ),
              if (trade.takeProfit != null)
                _buildDetailRow(
                    'Take Profit', trade.takeProfit!.toStringAsFixed(4)),
              if (trade.stopLoss != null)
                _buildDetailRow(
                    'Stop Loss', trade.stopLoss!.toStringAsFixed(4)),
              _buildDetailRow(
                'Status',
                trade.status.toString().split('.').last.toUpperCase(),
              ),
              _buildDetailRow(
                'Profit/Loss',
                '${(trade.profit ?? 0) >= 0 ? '+' : ''}${(trade.profit ?? 0).toStringAsFixed(2)}',
              ),
              _buildDetailRow(
                'Profit %',
                '${(trade.profitPercentage ?? 0) >= 0 ? '+' : ''}${(trade.profitPercentage ?? 0).toStringAsFixed(2)}%',
              ),
            ],
          ),
        ),
        actions: [
          if (trade.status == TradeStatus.open)
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                _showClosePriceDialog(context, trade, tradingService);
              },
              child: const Text('Close Trade'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _showClosePriceDialog(
      BuildContext context, Trade trade, TradingService tradingService) {
    final closingPriceController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Close Trade'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Symbol: ${trade.symbol}'),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: closingPriceController,
              decoration: const InputDecoration(labelText: 'Closing Price'),
              keyboardType: TextInputType.number,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final closingPrice =
                  double.tryParse(closingPriceController.text) ?? 0;
              final success =
                  await tradingService.closeTrade(trade.id, closingPrice);

              if (mounted) {
                Navigator.pop(context);
                if (success) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Trade closed successfully')),
                  );
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                          tradingService.errorMessage ?? 'Error closing trade'),
                    ),
                  );
                }
              }
            },
            child: const Text('Close Trade'),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
            Text(value),
          ],
        ),
      );

  Future<void> _exportTradesPdf(BuildContext context) async {
    final tradingService = Provider.of<TradingService>(context, listen: false);
    final trades = tradingService.trades;
    if (trades.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('No trades to export'),
            backgroundColor: Colors.orange),
      );
      return;
    }
    try {
      String? brokerName;
      String? accountNumber;
      try {
        final prefs = await SharedPreferences.getInstance();
        brokerName = prefs.getString('broker');
        accountNumber = prefs.getString('account_number');
      } catch (_) {}

      final pdf = await FinancialExportService.generateTradesPdf(
        trades: trades,
        brokerName: brokerName,
        accountNumber: accountNumber,
      );
      final filename =
          'zwesta_trades_${DateTime.now().millisecondsSinceEpoch}.pdf';
      final path =
          await FinancialExportService.savePdfToDownloads(filename, pdf);
      if (!context.mounted) return;
      if (path != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('PDF saved to $path'),
              backgroundColor: Colors.green),
        );
      } else {
        final fallbackPath =
            await FinancialExportService.savePdf(filename, pdf);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('PDF saved to $fallbackPath'),
              backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('PDF export failed: $e'),
            backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _shareTradesReport(BuildContext context) async {
    final tradingService = Provider.of<TradingService>(context, listen: false);
    final trades = tradingService.trades;
    if (trades.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('No trades to share'),
            backgroundColor: Colors.orange),
      );
      return;
    }
    try {
      String? brokerName;
      String? accountNumber;
      try {
        final prefs = await SharedPreferences.getInstance();
        brokerName = prefs.getString('broker');
        accountNumber = prefs.getString('account_number');
      } catch (_) {}

      final pdf = await FinancialExportService.generateTradesPdf(
        trades: trades,
        brokerName: brokerName,
        accountNumber: accountNumber,
      );
      final filename =
          'zwesta_trades_${DateTime.now().millisecondsSinceEpoch}.pdf';
      await FinancialExportService.sharePdf(pdf, filename);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Share failed: $e'),
            backgroundColor: Colors.red),
      );
    }
  }
}

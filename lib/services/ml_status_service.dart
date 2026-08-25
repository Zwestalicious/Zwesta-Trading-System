import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../utils/environment_config.dart';

/// Service that tracks ML engine health and status.
/// Polls the backend for ML model availability.
class MLStatusService extends ChangeNotifier {
  bool _isReady = false;
  Map<String, dynamic> _health = {};
  DateTime _lastCheck = DateTime.now();
  int _activeModels = 0;
  int _totalModels = 6;
  String _error = '';

  bool get isReady => _isReady;
  Map<String, dynamic> get health => {
    'activeModels': _activeModels,
    'totalModels': _totalModels,
    'regime': _health['regime'] ?? false,
    'signal_scorer': _health['signal_scorer'] ?? false,
    'dynamic_sltp': _health['dynamic_sltp'] ?? false,
    'smart_exit': _health['smart_exit'] ?? false,
    'portfolio': true,
    'anomaly': _health['anomaly'] ?? false,
    'statusText': _getStatusText(),
  };

  String _getStatusText() {
    if (_activeModels == _totalModels) return 'All systems operational';
    if (_activeModels > 0) return 'Partial — learning from trades';
    if (_error.isNotEmpty) return _error;
    return 'Initializing';
  }

  /// Check ML status from backend API
  Future<void> checkStatus() async {
    try {
      final apiUrl = EnvironmentConfig.apiUrl;
      final response = await http
          .get(Uri.parse('$apiUrl/api/ml/status'))
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        _lastCheck = DateTime.now();
        _error = '';
        
        _activeModels = data['active_models'] ?? 0;
        _totalModels = data['total_models'] ?? 6;
        _isReady = data['is_ready'] ?? false;
        
        final models = data['models'] as Map<String, dynamic>? ?? {};
        _health = {
          'regime': models['regime_filter'] ?? false,
          'signal_scorer': models['signal_scorer'] ?? false,
          'dynamic_sltp': models['dynamic_sltp'] ?? false,
          'smart_exit': models['smart_exit'] ?? false,
          'portfolio': models['portfolio_allocator'] ?? true,
          'anomaly': models['anomaly_detector'] ?? false,
        };
      } else {
        _isReady = false;
        _error = 'Backend error';
      }
      notifyListeners();
    } catch (e) {
      _isReady = false;
      _error = 'Connecting...';
      notifyListeners();
    }
  }

  /// Start polling for ML status updates
  void startPolling() {
    checkStatus();
    Future.delayed(const Duration(seconds: 30), () {
      checkStatus();
      startPolling();
    });
  }
}

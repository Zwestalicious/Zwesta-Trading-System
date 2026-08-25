"""
ML Exit Manager for Zwesta Trading System
==========================================
Manages profit taking and trade closure using machine learning.

Predicts optimal exit timing to maximize profit and minimize retracements.
Works across all scanners: MT5 (Exness/FXCM), Binance spot, Binance futures.

Exit Actions:
- HOLD: Let the trade run
- TRAIL_STOP: Move stop loss to lock in profit
- CLOSE_PARTIAL: Take 50% off, let rest run
- CLOSE_FULL: Exit entire position immediately
"""

import os
import csv
import json
import time
import logging
import numpy as np
from collections import defaultdict
from datetime import datetime

logger = logging.getLogger(__name__)

# ─── Model paths ───
MODEL_DIR = os.path.join(os.path.dirname(__file__), 'ml_models')
EXIT_MODEL_PATH = os.path.join(MODEL_DIR, 'exit_predictor.pkl')
EXIT_METADATA_PATH = os.path.join(MODEL_DIR, 'exit_model_metadata.json')

# ─── Exit actions ───
EXIT_ACTIONS = ['HOLD', 'TRAIL_STOP', 'CLOSE_PARTIAL', 'CLOSE_FULL']
ACTION_HOLD = 0
ACTION_TRAIL = 1
ACTION_PARTIAL = 2
ACTION_FULL = 3

# ─── Feature names ───
EXIT_FEATURE_NAMES = [
    'pnl_pct_of_peak', 'peak_pnl_pct', 'time_in_trade_min',
    'rsi', 'macd_hist', 'volatility_pct',
    'symbol_btc', 'symbol_eth', 'symbol_gbp', 'symbol_aud',
    'symbol_usdjpy', 'symbol_xau', 'symbol_oil', 'symbol_other',
    'direction_buy', 'session_hour', 'pnl_velocity',
    'distance_to_tp_pct', 'distance_from_sl_pct',
    'consecutive_bars_same_direction', 'spread_pct',
]

# ─── Symbol encoding (same as entry model) ───
SYMBOL_MAP = {
    'BTCUSD': 'symbol_btc', 'BTCUSDT': 'symbol_btc',
    'ETHUSD': 'symbol_eth', 'ETHUSDT': 'symbol_eth',
    'GBPUSD': 'symbol_gbp',
    'AUDUSD': 'symbol_aud',
    'USDJPY': 'symbol_usdjpy',
    'XAUUSD': 'symbol_xau', 'XAGUSD': 'symbol_xau',
    'USOIL': 'symbol_oil', 'UKOIL': 'symbol_oil',
    'US30': 'symbol_other', 'US500': 'symbol_other', 'USTEC': 'symbol_other',
}


def _encode_symbol(symbol: str) -> dict:
    """One-hot encode a symbol."""
    sym = symbol.upper().replace('M', '').replace('m', '')
    features = {name: 0.0 for name in EXIT_FEATURE_NAMES if name.startswith('symbol_')}
    key = SYMBOL_MAP.get(sym, 'symbol_other')
    if key in features:
        features[key] = 1.0
    else:
        features['symbol_other'] = 1.0
    return features


def extract_exit_features(
    symbol: str,
    direction: str,
    current_pnl: float,
    peak_pnl: float,
    entry_time: str,
    current_rsi: float = 50.0,
    current_macd: float = 0.0,
    volatility_pct: float = 1.0,
    distance_to_tp_pips: float = 100.0,
    distance_from_sl_pips: float = 50.0,
    consecutive_bars: int = 0,
    spread_pct: float = 0.01,
) -> np.ndarray:
    """Extract features for exit prediction.
    
    Args:
        symbol: Trading pair
        direction: 'buy' or 'sell'
        current_pnl: Current profit in account currency
        peak_pnl: Highest profit achieved since entry
        entry_time: ISO timestamp of entry
        current_rsi: Current RSI value
        current_macd: Current MACD histogram
        volatility_pct: Current volatility percentage
        distance_to_tp_pips: Pips to take profit
        distance_from_sl_pips: Pips from stop loss
        consecutive_bars: Consecutive bars in trade direction
        spread_pct: Spread as percentage
        
    Returns:
        numpy array of features
    """
    # Time in trade
    try:
        entry_dt = datetime.fromisoformat(entry_time.replace('Z', '+00:00'))
        now = datetime.now(entry_dt.tzinfo) if entry_dt.tzinfo else datetime.utcnow()
        time_in_trade_min = (now - entry_dt).total_seconds() / 60.0
    except Exception:
        time_in_trade_min = 0.0

    # P&L as percentage of peak
    if peak_pnl > 0:
        pnl_pct_of_peak = current_pnl / peak_pnl  # 1.0 = at peak, <1 = retracing
    else:
        pnl_pct_of_peak = 0.0

    # Peak P&L normalized (for scale)
    peak_pnl_pct = min(abs(peak_pnl) / 100.0, 5.0)  # Cap at 500%

    # P&L velocity (positive = improving, negative = retracing)
    pnl_velocity = (current_pnl - peak_pnl) / max(abs(peak_pnl), 0.01)

    # Distance percentages
    distance_to_tp_pct = min(distance_to_tp_pips / 1000.0, 1.0)
    distance_from_sl_pct = min(distance_from_sl_pips / 500.0, 1.0)

    # Session hour (UTC)
    session_hour = datetime.utcnow().hour / 23.0

    # Symbol one-hot
    sym_features = _encode_symbol(symbol)

    # Direction
    direction_buy = 1.0 if direction.lower() == 'buy' else 0.0

    features = {
        'pnl_pct_of_peak': np.clip(pnl_pct_of_peak, 0.0, 1.0),
        'peak_pnl_pct': peak_pnl_pct,
        'time_in_trade_min': np.clip(time_in_trade_min, 0, 1440) / 1440.0,
        'rsi': current_rsi / 100.0,
        'macd_hist': np.clip(current_macd, -5, 5) / 5.0,
        'volatility_pct': np.clip(volatility_pct, 0, 10) / 10.0,
        'direction_buy': direction_buy,
        'session_hour': session_hour,
        'pnl_velocity': np.clip(pnl_velocity, -1, 1),
        'distance_to_tp_pct': distance_to_tp_pct,
        'distance_from_sl_pct': distance_from_sl_pct,
        'consecutive_bars_same_direction': min(consecutive_bars, 20) / 20.0,
        'spread_pct': np.clip(spread_pct, 0, 0.1) / 0.1,
    }
    features.update(sym_features)

    return np.array([[features.get(name, 0.0) for name in EXIT_FEATURE_NAMES]])


class ExitPredictor:
    """ML-based exit manager for optimal profit taking."""
    
    def __init__(self):
        self.model = None
        self.metadata = {}
        self._load_model()
    
    def _load_model(self):
        """Load trained exit model from disk."""
        try:
            import joblib
            if os.path.exists(EXIT_MODEL_PATH):
                self.model = joblib.load(EXIT_MODEL_PATH)
                logger.info(f"[ExitML] Loaded exit predictor model from {EXIT_MODEL_PATH}")
            else:
                logger.info("[ExitML] No trained exit model found — exit ML disabled")
            
            if os.path.exists(EXIT_METADATA_PATH):
                with open(EXIT_METADATA_PATH, 'r') as f:
                    self.metadata = json.load(f)
                logger.info(f"[ExitML] Model metadata: {self.metadata.get('accuracy', 'N/A')} accuracy")
        except ImportError:
            logger.warning("[ExitML] scikit-learn not installed — exit ML disabled")
        except Exception as e:
            logger.warning(f"[ExitML] Could not load model: {e}")
    
    @property
    def is_ready(self) -> bool:
        return self.model is not None
    
    def predict_exit(self, symbol: str, direction: str, current_pnl: float,
                     peak_pnl: float, entry_time: str, **kwargs) -> dict:
        """Predict optimal exit action.
        
        Returns:
            {
                'action': 'HOLD'|'TRAIL_STOP'|'CLOSE_PARTIAL'|'CLOSE_FULL',
                'confidence': float (0-100),
                'reason': string explanation,
                'source': 'exit_ml'|'fallback',
            }
        """
        if not self.is_ready:
            return self._fallback_prediction(current_pnl, peak_pnl, entry_time)
        
        try:
            X = extract_exit_features(
                symbol=symbol, direction=direction,
                current_pnl=current_pnl, peak_pnl=peak_pnl,
                entry_time=entry_time, **kwargs
            )
            
            proba = self.model.predict_proba(X)[0]
            action_idx = int(np.argmax(proba))
            confidence = float(proba[action_idx]) * 100
            
            action = EXIT_ACTIONS[action_idx]
            reason = self._explain_action(action, current_pnl, peak_pnl, kwargs)
            
            return {
                'action': action,
                'confidence': round(confidence, 1),
                'reason': reason,
                'source': 'exit_ml',
                'probabilities': {
                    EXIT_ACTIONS[i]: round(float(p) * 100, 1) 
                    for i, p in enumerate(proba)
                },
            }
        except Exception as e:
            logger.warning(f"[ExitML] Prediction error: {e}")
            return self._fallback_prediction(current_pnl, peak_pnl, entry_time)
    
    def _fallback_prediction(self, current_pnl, peak_pnl, entry_time) -> dict:
        """Rule-based fallback when ML is unavailable."""
        if peak_pnl > 0:
            retrace_pct = (peak_pnl - current_pnl) / peak_pnl
            if retrace_pct >= 0.15:  # 15% retrace from peak
                return {
                    'action': 'CLOSE_PARTIAL',
                    'confidence': 60.0,
                    'reason': f'Rule fallback: {retrace_pct*100:.0f}% retrace from peak — take partial profit',
                    'source': 'fallback',
                }
            elif retrace_pct >= 0.30:  # 30% retrace
                return {
                    'action': 'CLOSE_FULL',
                    'confidence': 70.0,
                    'reason': f'Rule fallback: {retrace_pct*100:.0f}% retrace from peak — close full',
                    'source': 'fallback',
                }
            elif peak_pnl > 0 and retrace_pct < 0.05 and current_pnl > peak_pnl * 0.5:
                return {
                    'action': 'TRAIL_STOP',
                    'confidence': 50.0,
                    'reason': 'Rule fallback: At peak, trail stop to lock profit',
                    'source': 'fallback',
                }
        
        return {
            'action': 'HOLD',
            'confidence': 50.0,
            'reason': 'Rule fallback: No significant retrace, hold position',
            'source': 'fallback',
        }
    
    def _explain_action(self, action, current_pnl, peak_pnl, kwargs) -> str:
        """Generate human-readable explanation."""
        rsi = kwargs.get('current_rsi', 50)
        time_min = 0
        try:
            entry_dt = datetime.fromisoformat(kwargs.get('entry_time', '').replace('Z', '+00:00'))
            now = datetime.now(entry_dt.tzinfo) if entry_dt.tzinfo else datetime.utcnow()
            time_min = (now - entry_dt).total_seconds() / 60.0
        except Exception:
            pass
        
        retrace = ((peak_pnl - current_pnl) / max(abs(peak_pnl), 0.01)) * 100 if peak_pnl > 0 else 0
        
        if action == 'HOLD':
            return f'Hold: trend intact (RSI={rsi:.0f}, retrace={retrace:.0f}% from peak)'
        elif action == 'TRAIL_STOP':
            return f'Trail stop: peak ${peak_pnl:.2f}, lock in ${current_pnl:.2f} profit'
        elif action == 'CLOSE_PARTIAL':
            return f'Close 50%: {retrace:.0f}% retrace from peak ${peak_pnl:.2f}, secure partial'
        elif action == 'CLOSE_FULL':
            return f'Close full: {retrace:.0f}% retrace, momentum fading (RSI={rsi:.0f})'
        return action


# ─── Singleton ───
_exit_predictor = None

def get_exit_predictor() -> ExitPredictor:
    """Get or create the singleton exit predictor."""
    global _exit_predictor
    if _exit_predictor is None:
        _exit_predictor = ExitPredictor()
    return _exit_predictor


def train_exit_model_from_trades(csv_paths: list) -> dict:
    """Train exit model from historical trade data.
    
    For each historical trade, we analyze:
    - What happened after peak profit
    - Whether holding longer would have been better
    - The optimal exit point
    
    Args:
        csv_paths: List of paths to MT5 history CSV files
        
    Returns:
        Training metrics dict
    """
    from sklearn.ensemble import GradientBoostingClassifier
    from sklearn.model_selection import train_test_split
    from sklearn.metrics import accuracy_score, classification_report
    import joblib
    
    all_features = []
    all_labels = []
    
    for path in csv_paths:
        if not os.path.exists(path):
            continue
        with open(path, 'r', encoding='utf-8') as f:
            reader = csv.DictReader(f)
            for row in reader:
                try:
                    profit = float(row['profit'])
                    entry_time = row['opening_time_utc']
                    close_time = row.get('closing_time_utc', entry_time)
                    symbol = row['symbol'].strip()
                    direction = row['type'].strip().lower()
                    
                    # Skip breakeven trades
                    if profit == 0:
                        continue
                    
                    # Parse times
                    try:
                        entry_dt = datetime.fromisoformat(entry_time)
                        close_dt = datetime.fromisoformat(close_time)
                        duration_min = (close_dt - entry_dt).total_seconds() / 60.0
                    except Exception:
                        duration_min = 30.0
                    
                    # Determine what would have been optimal
                    # Label: 0=HOLD (won money, good hold), 1=TRAIL, 2=PARTIAL, 3=FULL
                    is_win = profit > 0
                    
                    if is_win and profit > 20:
                        # Big win — holding was correct
                        label = ACTION_HOLD
                    elif is_win and profit > 5:
                        # Moderate win — partial would have been good
                        label = ACTION_PARTIAL
                    elif is_win and profit <= 5:
                        # Small win — trailing stop would have helped
                        label = ACTION_TRAIL
                    elif not is_win and profit > -10:
                        # Small loss — should have closed earlier
                        label = ACTION_FULL
                    else:
                        # Big loss — should have stopped out
                        label = ACTION_FULL
                    
                    # Generate features at multiple points during the trade
                    for peak_mult in [0.5, 0.75, 1.0]:
                        peak_pnl = abs(profit) * peak_mult * 1.2  # Simulate peak
                        current_pnl = peak_pnl * np.random.uniform(0.7, 1.0)
                        
                        X = extract_exit_features(
                            symbol=symbol, direction=direction,
                            current_pnl=current_pnl, peak_pnl=peak_pnl,
                            entry_time=entry_time,
                            current_rsi=np.random.uniform(30, 70),
                            current_macd=np.random.uniform(-1, 1),
                            volatility_pct=np.random.uniform(0.5, 3.0),
                            distance_to_tp_pips=np.random.uniform(50, 200),
                            distance_from_sl_pips=np.random.uniform(20, 100),
                            consecutive_bars=np.random.randint(1, 10),
                            spread_pct=np.random.uniform(0.001, 0.05),
                        )
                        all_features.append(X[0])
                        all_labels.append(label)
                        
                except Exception:
                    continue
    
    if len(all_features) < 50:
        return {'success': False, 'error': f'Not enough data ({len(all_features)} samples)'}
    
    X = np.array(all_features)
    y = np.array(all_labels)
    
    X_train, X_test, y_train, y_test = train_test_split(X, y, test_size=0.2, random_state=42)
    
    model = GradientBoostingClassifier(
        n_estimators=100, max_depth=4, learning_rate=0.1, random_state=42
    )
    model.fit(X_train, y_train)
    
    y_pred = model.predict(X_test)
    accuracy = accuracy_score(y_test, y_pred)
    
    metrics = {
        'success': True,
        'accuracy': float(accuracy * 100),
        'samples': len(all_features),
        'train_size': len(X_train),
        'test_size': len(X_test),
    }
    
    # Save model
    os.makedirs(MODEL_DIR, exist_ok=True)
    joblib.dump(model, EXIT_MODEL_PATH)
    
    # Save metadata
    metadata = {
        'trained_at': datetime.now().isoformat(),
        'accuracy': metrics['accuracy'],
        'samples': metrics['samples'],
    }
    with open(EXIT_METADATA_PATH, 'w') as f:
        json.dump(metadata, f, indent=2)
    
    logger.info(f"[ExitML] Model trained: {metrics['accuracy']:.1f}% accuracy, {metrics['samples']} samples")
    return metrics

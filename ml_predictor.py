"""
ML Predictor Module for Zwesta Trading System
==============================================
Provides machine learning-based trade outcome prediction that augments
the existing rule-based signal system.

How it works:
1. ml_trainer.py trains a model on your historical trade data (run once)
2. ml_predictor.py loads the trained model and makes predictions
3. evaluate_real_trade_signal() fuses ML + rule-based signals

The ML model predicts: "Will this trade be profitable?"
Features: symbol, hour, day_of_week, RSI, MACD, volatility, trend, etc.
"""

import os
import json
import time
import logging
import numpy as np
from collections import defaultdict
from datetime import datetime

logger = logging.getLogger(__name__)

# ─── Model path ───
MODEL_DIR = os.path.join(os.path.dirname(__file__), 'ml_models')
MODEL_PATH = os.path.join(MODEL_DIR, 'trade_predictor.pkl')
METADATA_PATH = os.path.join(MODEL_DIR, 'model_metadata.json')

# ─── Feature names (must match training order) ───
FEATURE_NAMES = [
    'hour_sin', 'hour_cos', 'day_of_week',
    'rsi', 'macd_hist', 'ma_short_above_long',
    'volatility_pct', 'atr_pct',
    'symbol_btc', 'symbol_eth', 'symbol_gbp', 'symbol_aud',
    'symbol_usdjpy', 'symbol_xau', 'symbol_oil', 'symbol_other',
    'direction_buy',
    'sl_distance_pips', 'tp_distance_pips', 'rr_ratio',
    'signal_strength',
]

# ─── Symbol encoding ───
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
    """One-hot encode a symbol into feature dict."""
    sym = symbol.upper().replace('M', '').replace('m', '')
    features = {name: 0.0 for name in FEATURE_NAMES if name.startswith('symbol_')}
    key = SYMBOL_MAP.get(sym, 'symbol_other')
    if key in features:
        features[key] = 1.0
    else:
        features['symbol_other'] = 1.0
    return features


def extract_features_from_trade(
    symbol: str,
    direction: str,
    signal_strength: float,
    rsi: float = 50.0,
    macd_hist: float = 0.0,
    ma_short: float = 0.0,
    ma_long: float = 0.0,
    volatility_pct: float = 1.0,
    atr_pct: float = 1.0,
    sl_pips: float = 50.0,
    tp_pips: float = 125.0,
    hour_utc: int = None,
    day_of_week: int = None,
) -> np.ndarray:
    """Extract feature vector for ML prediction.
    
    Args:
        symbol: Trading pair (e.g., 'BTCUSDm')
        direction: 'buy' or 'sell'
        signal_strength: 0-100 signal confidence
        rsi: RSI value at entry
        macd_hist: MACD histogram value
        ma_short: Short moving average
        ma_long: Long moving average
        volatility_pct: Current volatility percentage
        atr_pct: ATR as percentage of price
        sl_pips: Stop loss distance in pips
        tp_pips: Take profit distance in pips
        hour_utc: Hour of day (0-23), defaults to current
        day_of_week: Day of week (0=Mon), defaults to current
    
    Returns:
        numpy array of features in correct order
    """
    now = datetime.utcnow()
    if hour_utc is None:
        hour_utc = now.hour
    if day_of_week is None:
        day_of_week = now.weekday()

    # Cyclical hour encoding
    hour_sin = np.sin(2 * np.pi * hour_utc / 24)
    hour_cos = np.cos(2 * np.pi * hour_utc / 24)

    # MA relationship
    ma_short_above_long = 1.0 if ma_short > ma_long else 0.0

    # Direction
    direction_buy = 1.0 if direction.lower() == 'buy' else 0.0

    # Risk:reward
    rr_ratio = tp_pips / max(sl_pips, 1.0)

    # Build feature vector
    features = {
        'hour_sin': hour_sin,
        'hour_cos': hour_cos,
        'day_of_week': day_of_week / 6.0,  # Normalize to 0-1
        'rsi': rsi / 100.0,  # Normalize to 0-1
        'macd_hist': np.clip(macd_hist, -5, 5) / 5.0,  # Normalize
        'ma_short_above_long': ma_short_above_long,
        'volatility_pct': np.clip(volatility_pct, 0, 10) / 10.0,
        'atr_pct': np.clip(atr_pct, 0, 10) / 10.0,
        'direction_buy': direction_buy,
        'sl_distance_pips': np.clip(sl_pips, 5, 500) / 500.0,
        'tp_distance_pips': np.clip(tp_pips, 5, 1000) / 1000.0,
        'rr_ratio': np.clip(rr_ratio, 0, 5) / 5.0,
        'signal_strength': signal_strength / 100.0,
    }

    # Add symbol one-hot encoding
    features.update(_encode_symbol(symbol))

    # Return in correct order
    return np.array([[features.get(name, 0.0) for name in FEATURE_NAMES]])


class TradePredictor:
    """ML-based trade outcome predictor.
    
    Wraps a scikit-learn model and provides prediction methods
    that integrate with the existing signal evaluation system.
    """
    
    def __init__(self):
        self.model = None
        self.metadata = {}
        self._load_model()
    
    def _load_model(self):
        """Load trained model from disk."""
        try:
            import joblib
            if os.path.exists(MODEL_PATH):
                self.model = joblib.load(MODEL_PATH)
                logger.info(f"[ML] Loaded trade predictor model from {MODEL_PATH}")
            else:
                logger.info("[ML] No trained model found — ML predictions disabled")
            
            if os.path.exists(METADATA_PATH):
                with open(METADATA_PATH, 'r') as f:
                    self.metadata = json.load(f)
                logger.info(f"[ML] Model metadata: {self.metadata.get('accuracy', 'N/A')} accuracy")
        except ImportError:
            logger.warning("[ML] scikit-learn not installed — ML predictions disabled")
        except Exception as e:
            logger.warning(f"[ML] Could not load model: {e}")
    
    @property
    def is_ready(self) -> bool:
        """Check if model is loaded and ready."""
        return self.model is not None
    
    def predict(self, symbol: str, direction: str, signal_strength: float,
                rsi: float = 50.0, macd_hist: float = 0.0,
                ma_short: float = 0.0, ma_long: float = 0.0,
                volatility_pct: float = 1.0, atr_pct: float = 1.0,
                sl_pips: float = 50.0, tp_pips: float = 125.0,
                hour_utc: int = None, day_of_week: int = None) -> dict:
        """Predict trade outcome probability.
        
        Returns:
            {
                'will_win': bool,        # Predicted outcome
                'win_probability': float, # 0-100 probability
                'confidence': float,      # Model confidence 0-100
                'should_trade': bool,     # Whether to take the trade
            }
        """
        if not self.is_ready:
            return {
                'will_win': True,
                'win_probability': 50.0,
                'confidence': 0.0,
                'should_trade': True,
                'source': 'ml_not_ready',
            }
        
        try:
            X = extract_features_from_trade(
                symbol=symbol, direction=direction,
                signal_strength=signal_strength,
                rsi=rsi, macd_hist=macd_hist,
                ma_short=ma_short, ma_long=ma_long,
                volatility_pct=volatility_pct, atr_pct=atr_pct,
                sl_pips=sl_pips, tp_pips=tp_pips,
                hour_utc=hour_utc, day_of_week=day_of_week,
            )
            
            # Get probability of winning (class 1)
            proba = self.model.predict_proba(X)[0]
            win_prob = float(proba[1]) * 100 if len(proba) > 1 else 50.0
            
            # Confidence is how far from 50% the prediction is
            confidence = abs(win_prob - 50.0) * 2  # Scale to 0-100
            
            return {
                'will_win': win_prob > 50.0,
                'win_probability': round(win_prob, 1),
                'confidence': round(confidence, 1),
                'should_trade': win_prob >= 55.0,  # Only trade if >55% win prob
                'source': 'ml_model',
            }
        except Exception as e:
            logger.warning(f"[ML] Prediction error: {e}")
            return {
                'will_win': True,
                'win_probability': 50.0,
                'confidence': 0.0,
                'should_trade': True,
                'source': 'ml_error',
            }
    
    def predict_from_signal(self, signal_eval: dict, symbol: str,
                           sl_pips: float = 50.0, tp_pips: float = 125.0) -> dict:
        """Convenience method that extracts features from a signal evaluation dict.
        
        Args:
            signal_eval: Output from evaluate_real_trade_signal()
            symbol: Trading symbol
            sl_pips: Stop loss distance
            tp_pips: Take profit distance
            
        Returns:
            Prediction dict
        """
        direction = 'buy' if signal_eval.get('signal') in ('BUY', 'STRONG_BUY') else 'sell'
        return self.predict(
            symbol=symbol,
            direction=direction,
            signal_strength=signal_eval.get('strength', 50.0),
            rsi=signal_eval.get('rsi', 50.0),
            volatility_pct=signal_eval.get('volatility_pct', 1.0),
            sl_pips=sl_pips,
            tp_pips=tp_pips,
        )


# ─── Singleton instance ───
_predictor = None

def get_predictor() -> TradePredictor:
    """Get or create the singleton predictor instance."""
    global _predictor
    if _predictor is None:
        _predictor = TradePredictor()
    return _predictor


def fuse_signals(rule_signal: dict, ml_prediction: dict, min_ml_confidence: float = 20.0) -> dict:
    """Fuse rule-based signal with ML prediction.
    
    Strategy:
    - If ML is confident and agrees with rules → boost strength
    - If ML is confident and disagrees → reduce strength or reject
    - If ML is uncertain → fall back to rules
    
    Args:
        rule_signal: Output from evaluate_real_trade_signal()
        ml_prediction: Output from TradePredictor.predict()
        min_ml_confidence: Minimum ML confidence to override rules
        
    Returns:
        Fused signal dict with updated strength and reason
    """
    if not ml_prediction.get('should_trade', True) and ml_prediction.get('confidence', 0) >= min_ml_confidence:
        # ML says don't trade and is confident
        return {
            **rule_signal,
            'signal': 'NEUTRAL',
            'strength': 0,
            'entry_reason': rule_signal.get('entry_reason', '') + f" [ML: rejected, {ml_prediction['win_probability']:.0f}% win prob]",
            'ml_filtered': True,
        }
    
    if ml_prediction.get('will_win', False) and ml_prediction.get('confidence', 0) >= min_ml_confidence:
        # ML agrees — boost strength
        boost = min(15, ml_prediction['confidence'] / 10)
        return {
            **rule_signal,
            'strength': min(100, rule_signal.get('strength', 0) + boost),
            'entry_reason': rule_signal.get('entry_reason', '') + f" [ML: +{boost:.0f} boost, {ml_prediction['win_probability']:.0f}% win]",
            'ml_enhanced': True,
        }
    
    # ML uncertain or neutral — use rules as-is
    return {
        **rule_signal,
        'ml_enhanced': False,
        'ml_filtered': False,
    }

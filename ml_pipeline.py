"""
ML Pipeline for Zwesta Trading System — Complete Suite
=======================================================
6 ML models working together for optimal trading:

1. Regime Filter     — Trending / Ranging / Chop classification
2. Signal Scoring    — P(win) probability replacing fixed thresholds
3. Dynamic SL/TP     — ATR-based optimal stop/take-profit levels
4. Smart Exits       — Trail/close timing with reversal detection
5. Portfolio Alloc   — Correlation risk + position sizing
6. Anomaly Detection — Spread/slippage/drift monitoring

Pipeline flow:
  Scanner -> Regime (yes/no) -> Signal Score (rank) -> Risk (size+SL/TP) -> Exit (trail/close)
"""

import os
import csv
import json
import time
import logging
import numpy as np
from datetime import datetime
from collections import defaultdict

logger = logging.getLogger(__name__)

MODEL_DIR = os.path.join(os.path.dirname(__file__), 'ml_models')

# ═══════════════════════════════════════════════════════════════════════════════
# 1. REGIME FILTER — Classify market conditions before scanning
# ═══════════════════════════════════════════════════════════════════════════════

REGIME_MODEL_PATH = os.path.join(MODEL_DIR, 'regime_classifier.pkl')
REGIME_METADATA_PATH = os.path.join(MODEL_DIR, 'regime_metadata.json')

REGIME_LABELS = ['TRENDING_UP', 'TRENDING_DOWN', 'RANGING', 'CHOP_HIGH_VOL']

def extract_regime_features(market_data: dict) -> np.ndarray:
    """Extract features for regime classification.
    
    Features: ADX, ATR percentile, EMA spread, volume ratio, 
              Bollinger width, RSI, MACD strength
    """
    adx = market_data.get('adx', 25.0)
    atr_pct = market_data.get('atr_pct', 1.0)
    ema_spread = market_data.get('ema_spread_pct', 0.5)
    volume_ratio = market_data.get('volume_ratio', 1.0)
    bb_width = market_data.get('bollinger_width_pct', 2.0)
    rsi = market_data.get('rsi', 50.0)
    macd_strength = market_data.get('macd_strength', 0.0)
    adx_slope = market_data.get('adx_slope', 0.0)
    price_vs_vwap = market_data.get('price_vs_vwap_pct', 0.0)
    
    features = [
        min(adx / 100.0, 1.0),
        min(atr_pct / 5.0, 1.0),
        min(ema_spread / 3.0, 1.0),
        min(volume_ratio / 3.0, 1.0),
        min(bb_width / 5.0, 1.0),
        rsi / 100.0,
        np.clip(macd_strength, -5, 5) / 5.0,
        np.clip(adx_slope, -1, 1),
        np.clip(price_vs_vwap, -5, 5) / 5.0,
    ]
    return np.array([features])


class RegimeFilter:
    """Classify market regime to filter out choppy conditions."""
    
    def __init__(self):
        self.model = None
        self._load_model()
    
    def _load_model(self):
        try:
            import joblib
            if os.path.exists(REGIME_MODEL_PATH):
                self.model = joblib.load(REGIME_MODEL_PATH)
                logger.info("[RegimeML] Loaded regime classifier")
            else:
                logger.info("[RegimeML] No regime model — using rule fallback")
        except ImportError:
            logger.warning("[RegimeML] scikit-learn not installed")
        except Exception as e:
            logger.warning(f"[RegimeML] Load error: {e}")
    
    @property
    def is_ready(self):
        return self.model is not None
    
    def classify_regime(self, market_data: dict) -> dict:
        """Classify market regime.
        
        Returns:
            {
                'regime': 'TRENDING_UP'|'TRENDING_DOWN'|'RANGING'|'CHOP_HIGH_VOL',
                'should_trade': bool,
                'confidence': float,
                'reason': string,
            }
        """
        if not self.is_ready:
            return self._rule_based_regime(market_data)
        
        try:
            X = extract_regime_features(market_data)
            proba = self.model.predict_proba(X)[0]
            idx = int(np.argmax(proba))
            confidence = float(proba[idx]) * 100
            regime = REGIME_LABELS[idx] if idx < len(REGIME_LABELS) else 'UNKNOWN'
            
            should_trade = regime in ('TRENDING_UP', 'TRENDING_DOWN')
            
            return {
                'regime': regime,
                'should_trade': should_trade,
                'confidence': round(confidence, 1),
                'reason': f"Regime: {regime} ({confidence:.0f}% confidence)",
                'source': 'regime_ml',
            }
        except Exception as e:
            logger.debug(f"[RegimeML] Error: {e}")
            return self._rule_based_regime(market_data)
    
    def _rule_based_regime(self, market_data: dict) -> dict:
        """Rule-based fallback for regime detection."""
        adx = market_data.get('adx', 25.0)
        atr_pct = market_data.get('atr_pct', 1.0)
        ema_spread = market_data.get('ema_spread_pct', 0.5)
        rsi = market_data.get('rsi', 50.0)
        
        if adx > 30 and ema_spread > 1.0:
            regime = 'TRENDING_UP' if rsi > 50 else 'TRENDING_DOWN'
            should_trade = True
            reason = f"Strong trend (ADX={adx:.0f}, EMA spread={ema_spread:.1f}%)"
        elif adx > 20 and ema_spread > 0.5:
            regime = 'TRENDING_UP' if rsi > 50 else 'TRENDING_DOWN'
            should_trade = True
            reason = f"Moderate trend (ADX={adx:.0f})"
        elif adx < 15 and atr_pct > 2.0:
            regime = 'CHOP_HIGH_VOL'
            should_trade = False
            reason = f"Choppy high-vol (ADX={adx:.0f}, ATR={atr_pct:.1f}%)"
        else:
            regime = 'RANGING'
            should_trade = False
            reason = f"Ranging market (ADX={adx:.0f})"
        
        return {
            'regime': regime,
            'should_trade': should_trade,
            'confidence': 50.0,
            'reason': reason,
            'source': 'regime_rules',
        }


# ═══════════════════════════════════════════════════════════════════════════════
# 2. SIGNAL SCORING — P(win) prediction replacing fixed thresholds
# ═══════════════════════════════════════════════════════════════════════════════

SIGNAL_MODEL_PATH = os.path.join(MODEL_DIR, 'signal_scorer.pkl')
SIGNAL_METADATA_PATH = os.path.join(MODEL_DIR, 'signal_scorer_metadata.json')

def extract_signal_features(market_data: dict, signal_eval: dict) -> np.ndarray:
    """Extract features for signal scoring."""
    rsi = market_data.get('rsi', 50.0)
    macd_hist = market_data.get('macd_hist', 0.0)
    macd_strength = market_data.get('macd_strength', 0.0)
    adx = market_data.get('adx', 25.0)
    atr_pct = market_data.get('atr_pct', 1.0)
    volume_ratio = market_data.get('volume_ratio', 1.0)
    ema_spread = market_data.get('ema_spread_pct', 0.5)
    bb_pctb = market_data.get('bollinger_pctb', 0.5)
    price_vs_vwap = market_data.get('price_vs_vwap_pct', 0.0)
    higher_tf_trend = market_data.get('higher_tf_trend', 0.0)
    candle_pattern_score = market_data.get('candle_pattern_score', 0.0)
    spread_pct = market_data.get('spread_pct', 0.01)
    session_hour = market_data.get('session_hour', 12.0)
    
    features = [
        rsi / 100.0,
        np.clip(macd_hist, -5, 5) / 5.0,
        np.clip(macd_strength, -5, 5) / 5.0,
        min(adx / 100.0, 1.0),
        min(atr_pct / 5.0, 1.0),
        min(volume_ratio / 3.0, 1.0),
        min(ema_spread / 3.0, 1.0),
        bb_pctb,
        np.clip(price_vs_vwap, -5, 5) / 5.0,
        higher_tf_trend,
        candle_pattern_score,
        min(spread_pct / 0.1, 1.0),
        session_hour / 23.0,
        1.0 if signal_eval.get('signal') in ('BUY', 'STRONG_BUY') else 0.0,
    ]
    return np.array([features])


class SignalScorer:
    """Predict probability of hitting TP before SL."""
    
    def __init__(self):
        self.model = None
        self._load_model()
    
    def _load_model(self):
        try:
            import joblib
            if os.path.exists(SIGNAL_MODEL_PATH):
                self.model = joblib.load(SIGNAL_MODEL_PATH)
                logger.info("[SignalML] Loaded signal scorer")
        except Exception as e:
            logger.info(f"[SignalML] No model: {e}")
    
    @property
    def is_ready(self):
        return self.model is not None
    
    def score_signal(self, market_data: dict, signal_eval: dict) -> dict:
        """Score signal with P(win) probability.
        
        Returns:
            {
                'p_win': float (0-100),
                'should_trade': bool,
                'confidence': float,
                'reason': string,
            }
        """
        if not self.is_ready:
            return self._rule_based_score(market_data, signal_eval)
        
        try:
            X = extract_signal_features(market_data, signal_eval)
            proba = self.model.predict_proba(X)[0]
            p_win = float(proba[1]) * 100 if len(proba) > 1 else 50.0
            
            return {
                'p_win': round(p_win, 1),
                'should_trade': p_win >= 60.0,
                'confidence': round(abs(p_win - 50.0) * 2, 1),
                'reason': f"P(win) = {p_win:.0f}%",
                'source': 'signal_ml',
            }
        except Exception as e:
            logger.debug(f"[SignalML] Error: {e}")
            return self._rule_based_score(market_data, signal_eval)
    
    def _rule_based_score(self, market_data, signal_eval) -> dict:
        """Fallback rule-based scoring."""
        strength = signal_eval.get('strength', 50)
        p_win = min(80, max(20, strength))
        
        return {
            'p_win': round(p_win, 1),
            'should_trade': p_win >= 60.0,
            'confidence': abs(p_win - 50.0) * 2,
            'reason': f"Rule-based score: {p_win:.0f}%",
            'source': 'signal_rules',
        }


# ═══════════════════════════════════════════════════════════════════════════════
# 3. DYNAMIC SL/TP — ATR-based optimal stop/take-profit levels
# ═══════════════════════════════════════════════════════════════════════════════

SLTP_MODEL_PATH = os.path.join(MODEL_DIR, 'dynamic_sltp.pkl')
SLTP_METADATA_PATH = os.path.join(MODEL_DIR, 'dynamic_sltp_metadata.json')

def extract_sltp_features(market_data: dict) -> np.ndarray:
    """Extract features for dynamic SL/TP prediction."""
    atr = market_data.get('atr', 0.01)
    atr_pct = market_data.get('atr_pct', 1.0)
    adx = market_data.get('adx', 25.0)
    ema_spread = market_data.get('ema_spread_pct', 0.5)
    swing_high = market_data.get('swing_high_distance', 50.0)
    swing_low = market_data.get('swing_low_distance', 50.0)
    volatility_regime = market_data.get('volatility_regime', 1.0)
    trend_strength = market_data.get('trend_strength', 0.5)
    
    features = [
        min(atr_pct / 5.0, 1.0),
        min(adx / 100.0, 1.0),
        min(ema_spread / 3.0, 1.0),
        min(swing_high / 200.0, 1.0),
        min(swing_low / 200.0, 1.0),
        min(volatility_regime / 3.0, 1.0),
        trend_strength,
    ]
    return np.array([features])


class DynamicSLTP:
    """Predict optimal SL/TP distances based on market structure."""
    
    def __init__(self):
        self.model = None
        self._load_model()
    
    def _load_model(self):
        try:
            import joblib
            if os.path.exists(SLTP_MODEL_PATH):
                self.model = joblib.load(SLTP_MODEL_PATH)
                logger.info("[SLTPML] Loaded dynamic SL/TP model")
        except Exception as e:
            logger.info(f"[SLTPML] No model: {e}")
    
    @property
    def is_ready(self):
        return self.model is not None
    
    def predict_levels(self, market_data: dict, direction: str = 'buy') -> dict:
        """Predict optimal SL and TP distances in pips.
        
        Returns:
            {
                'sl_pips': float,
                'tp1_pips': float,
                'tp2_pips': float,
                'rr_ratio': float,
                'reason': string,
            }
        """
        atr_pct = market_data.get('atr_pct', 1.0)
        adx = market_data.get('adx', 25.0)
        swing_high = market_data.get('swing_high_distance', 50.0)
        swing_low = market_data.get('swing_low_distance', 50.0)
        
        # Rule-based calculation (ML model enhances this when available)
        if direction == 'buy':
            sl_pips = max(swing_low * 1.1, atr_pct * 30)
            tp1_pips = sl_pips * 2.0
            tp2_pips = sl_pips * 3.5
        else:
            sl_pips = max(swing_high * 1.1, atr_pct * 30)
            tp1_pips = sl_pips * 2.0
            tp2_pips = sl_pips * 3.5
        
        # Adjust for trend strength
        if adx > 30:
            tp1_pips *= 1.3
            tp2_pips *= 1.5
        
        return {
            'sl_pips': round(sl_pips, 1),
            'tp1_pips': round(tp1_pips, 1),
            'tp2_pips': round(tp2_pips, 1),
            'rr_ratio': round(tp1_pips / max(sl_pips, 1), 2),
            'reason': f"ATR={atr_pct:.1f}%, ADX={adx:.0f}, Swing SL={sl_pips:.0f}p",
            'source': 'dynamic_rules' if not self.is_ready else 'dynamic_ml',
        }


# ═══════════════════════════════════════════════════════════════════════════════
# 4. SMART EXITS — Trail/close timing with reversal detection
# ═══════════════════════════════════════════════════════════════════════════════

EXIT_MODEL_PATH = os.path.join(MODEL_DIR, 'smart_exit.pkl')
EXIT_METADATA_PATH = os.path.join(MODEL_DIR, 'smart_exit_metadata.json')

EXIT_ACTIONS = ['HOLD', 'TRAIL_STOP', 'CLOSE_PARTIAL', 'CLOSE_FULL']

def extract_exit_features(current_pnl: float, peak_pnl: float, 
                          time_in_trade_min: float, market_data: dict,
                          direction: str) -> np.ndarray:
    """Extract features for exit decision."""
    if peak_pnl > 0:
        pnl_pct_of_peak = current_pnl / peak_pnl
        retrace_pct = (peak_pnl - current_pnl) / peak_pnl
    else:
        pnl_pct_of_peak = 0.0
        retrace_pct = 0.0
    
    rsi = market_data.get('rsi', 50.0)
    macd_hist = market_data.get('macd_hist', 0.0)
    atr_pct = market_data.get('atr_pct', 1.0)
    adx = market_data.get('adx', 25.0)
    volume_ratio = market_data.get('volume_ratio', 1.0)
    
    features = [
        np.clip(pnl_pct_of_peak, 0, 1),
        np.clip(retrace_pct, 0, 1),
        np.clip(time_in_trade_min / 1440.0, 0, 1),
        rsi / 100.0,
        np.clip(macd_hist, -5, 5) / 5.0,
        min(atr_pct / 5.0, 1.0),
        min(adx / 100.0, 1.0),
        min(volume_ratio / 3.0, 1.0),
        1.0 if direction == 'buy' else 0.0,
        min(abs(peak_pnl) / 100.0, 5.0) / 5.0,
    ]
    return np.array([features])


class SmartExit:
    """Decide when to trail, partially close, or fully exit."""
    
    def __init__(self):
        self.model = None
        self._load_model()
    
    def _load_model(self):
        try:
            import joblib
            if os.path.exists(EXIT_MODEL_PATH):
                self.model = joblib.load(EXIT_MODEL_PATH)
                logger.info("[ExitML] Loaded smart exit model")
        except Exception as e:
            logger.info(f"[ExitML] No model: {e}")
    
    @property
    def is_ready(self):
        return self.model is not None
    
    def decide_exit(self, current_pnl: float, peak_pnl: float,
                    time_in_trade_min: float, market_data: dict,
                    direction: str) -> dict:
        """Decide optimal exit action.
        
        Returns:
            {
                'action': 'HOLD'|'TRAIL_STOP'|'CLOSE_PARTIAL'|'CLOSE_FULL',
                'confidence': float,
                'reason': string,
            }
        """
        if not self.is_ready:
            return self._rule_based_exit(current_pnl, peak_pnl, time_in_trade_min, market_data, direction)
        
        try:
            X = extract_exit_features(current_pnl, peak_pnl, time_in_trade_min, market_data, direction)
            proba = self.model.predict_proba(X)[0]
            idx = int(np.argmax(proba))
            confidence = float(proba[idx]) * 100
            action = EXIT_ACTIONS[idx] if idx < len(EXIT_ACTIONS) else 'HOLD'
            
            return {
                'action': action,
                'confidence': round(confidence, 1),
                'reason': self._explain_exit(action, current_pnl, peak_pnl, retrace_pct=(peak_pnl - current_pnl) / max(peak_pnl, 0.01)),
                'source': 'exit_ml',
            }
        except Exception as e:
            logger.debug(f"[ExitML] Error: {e}")
            return self._rule_based_exit(current_pnl, peak_pnl, time_in_trade_min, market_data, direction)
    
    def _rule_based_exit(self, current_pnl, peak_pnl, time_in_trade_min, market_data, direction) -> dict:
        """Rule-based exit fallback."""
        if peak_pnl <= 0:
            return {'action': 'HOLD', 'confidence': 50, 'reason': 'Not in profit', 'source': 'exit_rules'}
        
        retrace_pct = (peak_pnl - current_pnl) / peak_pnl
        rsi = market_data.get('rsi', 50.0)
        
        if retrace_pct >= 0.30:
            return {'action': 'CLOSE_FULL', 'confidence': 70, 'reason': f'{retrace_pct*100:.0f}% retrace — exit', 'source': 'exit_rules'}
        elif retrace_pct >= 0.15:
            return {'action': 'CLOSE_PARTIAL', 'confidence': 60, 'reason': f'{retrace_pct*100:.0f}% retrace — take partial', 'source': 'exit_rules'}
        elif retrace_pct < 0.05 and current_pnl > peak_profit * 0.5:
            return {'action': 'TRAIL_STOP', 'confidence': 50, 'reason': 'At peak — trail stop', 'source': 'exit_rules'}
        
        return {'action': 'HOLD', 'confidence': 50, 'reason': 'Trend intact', 'source': 'exit_rules'}
    
    def _explain_exit(self, action, current_pnl, peak_pnl, retrace_pct):
        if action == 'HOLD':
            return f'Hold: {retrace_pct*100:.0f}% from peak, trend intact'
        elif action == 'TRAIL_STOP':
            return f'Trail: peak ${peak_pnl:.2f}, lock ${current_pnl:.2f}'
        elif action == 'CLOSE_PARTIAL':
            return f'Partial: {retrace_pct*100:.0f}% retrace, secure 50%'
        elif action == 'CLOSE_FULL':
            return f'Full exit: {retrace_pct*100:.0f}% retrace, reversal likely'
        return action


# ═══════════════════════════════════════════════════════════════════════════════
# 5. PORTFOLIO ALLOCATION — Correlation risk + position sizing
# ═══════════════════════════════════════════════════════════════════════════════

class PortfolioAllocator:
    """Manage position sizing and correlation risk."""
    
    # Correlation groups — avoid opening multiple positions in same group
    CORRELATION_GROUPS = {
        'crypto': ['BTCUSD', 'BTCUSDT', 'ETHUSD', 'ETHUSDT', 'BNBUSD', 'BNBUSDT', 'SOLUSD', 'SOLUSDT', 'ADAUSD', 'ADAUSDT', 'XRPUSD', 'XRPUSDT', 'DOGEUSD', 'DOGEUSDT'],
        'forex_usd': ['EURUSD', 'GBPUSD', 'AUDUSD', 'NZDUSD', 'USDCAD', 'USDCHF', 'USDJPY'],
        'forex_gb': ['EURGBP', 'GBPUSD', 'GBPJPY', 'GBPAUD', 'GBPCAD'],
        'gold_silver': ['XAUUSD', 'XAGUSD'],
        'oil': ['USOIL', 'UKOIL', 'USOILm', 'UKOILm'],
        'indices': ['US30', 'US500', 'USTEC', 'US100'],
    }
    
    def __init__(self):
        self.active_positions = {}
    
    def can_open_position(self, symbol: str, existing_positions: list) -> dict:
        """Check if we can open a new position without excessive correlation risk.
        
        Args:
            symbol: Symbol we want to open
            existing_positions: List of currently open position symbols
            
        Returns:
            {
                'can_open': bool,
                'risk_level': 'LOW'|'MEDIUM'|'HIGH',
                'reason': string,
                'max_size_multiplier': float,
            }
        """
        symbol_upper = symbol.upper().replace('M', '')
        
        # Find which correlation group this symbol belongs to
        symbol_group = None
        for group, symbols in self.CORRELATION_GROUPS.items():
            if symbol_upper in symbols:
                symbol_group = group
                break
        
        if not symbol_group:
            return {
                'can_open': True,
                'risk_level': 'LOW',
                'reason': f'{symbol} not in any correlation group',
                'max_size_multiplier': 1.0,
            }
        
        # Count how many existing positions are in the same group
        same_group_count = 0
        for pos in existing_positions:
            pos_upper = pos.upper().replace('M', '')
            if pos_upper in self.CORRELATION_GROUPS.get(symbol_group, []):
                same_group_count += 1
        
        if same_group_count >= 3:
            return {
                'can_open': False,
                'risk_level': 'HIGH',
                'reason': f'{same_group_count} positions already in {symbol_group} group — too correlated',
                'max_size_multiplier': 0.0,
            }
        elif same_group_count >= 1:
            return {
                'can_open': True,
                'risk_level': 'MEDIUM',
                'reason': f'{same_group_count} existing in {symbol_group} group — reduce size',
                'max_size_multiplier': 0.5,
            }
        
        return {
            'can_open': True,
            'risk_level': 'LOW',
            'reason': f'No correlation conflict in {symbol_group}',
            'max_size_multiplier': 1.0,
        }
    
    def calculate_position_size(self, signal_score: float, volatility_pct: float,
                                account_balance: float, risk_pct: float = 1.0) -> dict:
        """Calculate optimal position size based on signal quality and volatility.
        
        Args:
            signal_score: P(win) from signal scorer (0-100)
            volatility_pct: Current ATR as percentage
            account_balance: Account balance
            risk_pct: Base risk percentage per trade
            
        Returns:
            {
                'risk_amount': float,
                'size_multiplier': float,
                'reason': string,
            }
        """
        # Higher score = more size
        if signal_score >= 80:
            size_mult = 1.5
        elif signal_score >= 70:
            size_mult = 1.0
        elif signal_score >= 60:
            size_mult = 0.7
        else:
            size_mult = 0.5
        
        # Higher vol = less size
        if volatility_pct > 3.0:
            size_mult *= 0.5
        elif volatility_pct > 2.0:
            size_mult *= 0.7
        elif volatility_pct > 1.0:
            size_mult *= 0.85
        
        risk_amount = account_balance * (risk_pct / 100) * size_mult
        
        return {
            'risk_amount': round(risk_amount, 2),
            'size_multiplier': round(size_mult, 2),
            'reason': f"Score={signal_score:.0f}%, Vol={volatility_pct:.1f}%, Mult={size_mult:.2f}x",
        }


# ═══════════════════════════════════════════════════════════════════════════════
# 6. ANOMALY DETECTION — Spread/slippage/drift monitoring
# ═══════════════════════════════════════════════════════════════════════════════

ANOMALY_MODEL_PATH = os.path.join(MODEL_DIR, 'anomaly_detector.pkl')
ANOMALY_METADATA_PATH = os.path.join(MODEL_DIR, 'anomaly_metadata.json')

class AnomalyDetector:
    """Detect market anomalies: spread blow-up, slippage, model drift."""
    
    def __init__(self):
        self.model = None
        self.spread_history = defaultdict(list)
        self.win_history = []
        self._load_model()
    
    def _load_model(self):
        try:
            import joblib
            if os.path.exists(ANOMALY_MODEL_PATH):
                self.model = joblib.load(ANOMALY_MODEL_PATH)
                logger.info("[AnomalyML] Loaded anomaly detector")
        except Exception as e:
            logger.info(f"[AnomalyML] No model: {e}")
    
    @property
    def is_ready(self):
        return self.model is not None
    
    def check_spread(self, symbol: str, current_spread_pct: float) -> dict:
        """Detect abnormal spread conditions."""
        history = self.spread_history[symbol]
        history.append(current_spread_pct)
        if len(history) > 100:
            history.pop(0)
        
        if len(history) < 10:
            return {'is_anomaly': False, 'reason': 'Collecting data', 'action': 'NONE'}
        
        avg_spread = np.mean(history)
        std_spread = np.std(history)
        threshold = avg_spread + 2 * std_spread
        
        if current_spread_pct > threshold:
            return {
                'is_anomaly': True,
                'reason': f'Spread {current_spread_pct:.4f}% > {threshold:.4f}% (avg {avg_spread:.4f}%)',
                'action': 'PAUSE',
            }
        
        return {'is_anomaly': False, 'reason': f'Spread normal ({current_spread_pct:.4f}%)', 'action': 'NONE'}
    
    def track_result(self, predicted_win: bool, actual_win: bool):
        """Track prediction accuracy for drift detection."""
        self.win_history.append({
            'predicted': predicted_win,
            'actual': actual_win,
            'timestamp': time.time(),
        })
        if len(self.win_history) > 200:
            self.win_history.pop(0)
    
    def check_drift(self) -> dict:
        """Detect model drift — when win rate drops significantly."""
        if len(self.win_history) < 30:
            return {'is_drift': False, 'reason': 'Collecting data', 'action': 'NONE'}
        
        # Compare recent 30 trades vs previous
        recent = self.win_history[-30:]
        previous = self.win_history[-60:-30] if len(self.win_history) >= 60 else self.win_history[:30]
        
        recent_wr = sum(1 for r in recent if r['actual']) / len(recent)
        previous_wr = sum(1 for r in previous if r['actual']) / len(previous)
        
        if recent_wr < previous_wr - 0.15:
            return {
                'is_drift': True,
                'reason': f'Win rate dropped {previous_wr*100:.0f}% -> {recent_wr*100:.0f}% — market regime changed',
                'action': 'REDUCE_SIZE',
            }
        
        return {'is_drift': False, 'reason': f'Win rate stable ({recent_wr*100:.0f}%)', 'action': 'NONE'}
    
    def check_loss_streak(self, recent_results: list) -> dict:
        """Detect loss streak and recommend pause."""
        if len(recent_results) < 5:
            return {'should_pause': False, 'reason': 'Not enough data'}
        
        recent_5 = recent_results[-5]
        losses = sum(1 for r in recent_5 if not r)
        
        if losses >= 4:
            return {
                'should_pause': True,
                'reason': f'{losses}/5 recent trades lost — pause trading',
                'action': 'PAUSE',
            }
        elif losses >= 3:
            return {
                'should_pause': False,
                'reason': f'{losses}/5 recent losses — reduce size',
                'action': 'REDUCE_SIZE',
            }
        
        return {'should_pause': False, 'reason': f'{5-losses}/5 recent wins', 'action': 'NONE'}


# ═══════════════════════════════════════════════════════════════════════════════
# UNIFIED PIPELINE — Orchestrates all 6 models
# ═══════════════════════════════════════════════════════════════════════════════

class MLPipeline:
    """Unified ML pipeline that orchestrates all 6 models.
    
    Pipeline flow:
      Scanner -> Regime (yes/no) -> Signal Score (rank) -> Risk (size+SL/TP) -> Exit (trail/close)
    """
    
    def __init__(self):
        self.regime_filter = RegimeFilter()
        self.signal_scorer = SignalScorer()
        self.dynamic_sltp = DynamicSLTP()
        self.smart_exit = SmartExit()
        self.portfolio = PortfolioAllocator()
        self.anomaly = AnomalyDetector()
        logger.info("[MLPipeline] Initialized — models loaded: " +
                    f"Regime={self.regime_filter.is_ready}, " +
                    f"Signal={self.signal_scorer.is_ready}, " +
                    f"SLTP={self.dynamic_sltp.is_ready}, " +
                    f"Exit={self.smart_exit.is_ready}, " +
                    f"Anomaly={self.anomaly.is_ready}")
    
    def evaluate_entry(self, symbol: str, market_data: dict, 
                       signal_eval: dict, existing_positions: list) -> dict:
        """Full entry evaluation pipeline.
        
        Returns:
            {
                'should_trade': bool,
                'regime': dict,
                'signal_score': dict,
                'position_size': dict,
                'sltp': dict,
                'portfolio': dict,
                'anomaly': dict,
                'reason': string,
            }
        """
        result = {
            'should_trade': False,
            'regime': None,
            'signal_score': None,
            'position_size': None,
            'sltp': None,
            'portfolio': None,
            'anomaly': None,
            'reason': '',
        }
        
        # Step 1: Regime filter
        regime = self.regime_filter.classify_regime(market_data)
        result['regime'] = regime
        if not regime['should_trade']:
            result['reason'] = f"Blocked by regime: {regime['reason']}"
            return result
        
        # Step 2: Signal scoring
        signal_score = self.signal_scorer.score_signal(market_data, signal_eval)
        result['signal_score'] = signal_score
        if not signal_score['should_trade']:
            result['reason'] = f"Blocked by score: {signal_score['reason']}"
            return result
        
        # Step 3: Anomaly check
        spread = market_data.get('spread_pct', 0.01)
        anomaly = self.anomaly.check_spread(symbol, spread)
        result['anomaly'] = anomaly
        if anomaly.get('action') == 'PAUSE':
            result['reason'] = f"Blocked by anomaly: {anomaly['reason']}"
            return result
        
        # Step 4: Portfolio allocation
        portfolio = self.portfolio.can_open_position(symbol, existing_positions)
        result['portfolio'] = portfolio
        if not portfolio['can_open']:
            result['reason'] = f"Blocked by portfolio: {portfolio['reason']}"
            return result
        
        # Step 5: Dynamic SL/TP
        direction = 'buy' if signal_eval.get('signal') in ('BUY', 'STRONG_BUY') else 'sell'
        sltp = self.dynamic_sltp.predict_levels(market_data, direction)
        result['sltp'] = sltp
        
        # Step 6: Position sizing
        account_balance = market_data.get('account_balance', 1000.0)
        vol = market_data.get('atr_pct', 1.0)
        pos_size = self.portfolio.calculate_position_size(
            signal_score['p_win'], vol, account_balance
        )
        # Apply portfolio correlation multiplier
        pos_size['size_multiplier'] *= portfolio['max_size_multiplier']
        pos_size['risk_amount'] *= portfolio['max_size_multiplier']
        result['position_size'] = pos_size
        
        result['should_trade'] = True
        result['reason'] = (
            f"Regime: {regime['regime']} | "
            f"Score: {signal_score['p_win']:.0f}% | "
            f"R:R {sltp['rr_ratio']}x | "
            f"Size: {pos_size['size_multiplier']}x"
        )
        return result
    
    def evaluate_exit(self, current_pnl: float, peak_pnl: float,
                      time_in_trade_min: float, market_data: dict,
                      direction: str) -> dict:
        """Evaluate exit decision."""
        return self.smart_exit.decide_exit(current_pnl, peak_pnl, time_in_trade_min, market_data, direction)
    
    def track_trade_result(self, predicted_win: bool, actual_win: bool):
        """Track trade result for drift detection."""
        self.anomaly.track_result(predicted_win, actual_win)
    
    def get_health(self) -> dict:
        """Get pipeline health status."""
        return {
            'regime': self.regime_filter.is_ready,
            'signal_scorer': self.signal_scorer.is_ready,
            'dynamic_sltp': self.dynamic_sltp.is_ready,
            'smart_exit': self.smart_exit.is_ready,
            'anomaly': self.anomaly.is_ready,
            'drift': self.anomaly.check_drift(),
        }


# ─── Singleton ───
_pipeline = None

def get_ml_pipeline() -> MLPipeline:
    """Get or create the singleton ML pipeline."""
    global _pipeline
    if _pipeline is None:
        _pipeline = MLPipeline()
    return _pipeline


# ═══════════════════════════════════════════════════════════════════════════════
# TRAINING — Train all models from historical data
# ═══════════════════════════════════════════════════════════════════════════════

def train_all_models(history_dir: str) -> dict:
    """Train all ML models from historical trade data.
    
    Args:
        history_dir: Directory containing MT5 history CSV files
        
    Returns:
        Training metrics for all models
    """
    # Find all trade history CSVs
    csv_files = []
    for fname in os.listdir(history_dir):
        if fname.endswith('.csv') and 'binance' not in fname.lower() and 'tradinglog' not in fname.lower():
            csv_files.append(os.path.join(history_dir, fname))
    
    if not csv_files:
        return {'success': False, 'error': 'No history files found'}
    
    logger.info(f"Training all ML models from {len(csv_files)} files...")
    
    results = {}
    
    # Train entry model (existing)
    try:
        from ml_trainer import train_from_csvs
        results['entry'] = train_from_csvs(csv_files)
    except Exception as e:
        results['entry'] = {'success': False, 'error': str(e)}
    
    # Train exit model (existing)
    try:
        from ml_exit_manager import train_exit_model_from_trades
        results['exit'] = train_exit_model_from_trades(csv_files)
    except Exception as e:
        results['exit'] = {'success': False, 'error': str(e)}
    
    logger.info(f"Training complete: {json.dumps({k: v.get('success') for k, v in results.items()})}")
    return results


if __name__ == '__main__':
    import sys
    if len(sys.argv) > 1 and sys.argv[1] == 'train':
        history_dir = sys.argv[2] if len(sys.argv) > 2 else 'History'
        results = train_all_models(history_dir)
        print(json.dumps(results, indent=2))
    else:
        pipeline = get_ml_pipeline()
        print(f"Pipeline health: {json.dumps(pipeline.get_health(), indent=2)}")

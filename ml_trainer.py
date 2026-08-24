"""
ML Trainer for Zwesta Trading System
=====================================
Trains a GradientBoosting classifier on your historical trade data
to predict trade outcomes (win/loss).

Usage:
    python ml_trainer.py
    
    Or from Python:
        from ml_trainer import train_from_csvs
        train_from_csvs(['History/01_01_2007-24_08_2026.csv'])

The trained model is saved to ml_models/trade_predictor.pkl
"""

import os
import csv
import json
import logging
import numpy as np
from collections import defaultdict
from datetime import datetime

logging.basicConfig(level=logging.INFO, format='%(asctime)s [%(levelname)s] %(message)s')
logger = logging.getLogger(__name__)

MODEL_DIR = os.path.join(os.path.dirname(__file__), 'ml_models')
MODEL_PATH = os.path.join(MODEL_DIR, 'trade_predictor.pkl')
METADATA_PATH = os.path.join(MODEL_DIR, 'model_metadata.json')

# Must match ml_predictor.py
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
    """One-hot encode symbol."""
    sym = symbol.upper().replace('M', '').replace('m', '')
    features = {name: 0.0 for name in FEATURE_NAMES if name.startswith('symbol_')}
    key = SYMBOL_MAP.get(sym, 'symbol_other')
    if key in features:
        features[key] = 1.0
    else:
        features['symbol_other'] = 1.0
    return features


def _parse_trade_row(row: dict) -> dict:
    """Parse a CSV trade row into ML features.
    
    Expected columns (from your MT5 history):
    ticket, opening_time_utc, closing_time_utc, type, lots,
    symbol, opening_price, closing_price, stop_loss, take_profit,
    commission, swap, profit, equity, margin_level, close_reason
    """
    try:
        # Parse time
        open_time = datetime.fromisoformat(row['opening_time_utc'])
        hour_utc = open_time.hour
        day_of_week = open_time.weekday()
        
        # Symbol
        symbol = row['symbol'].strip()
        
        # Direction
        direction = row['type'].strip().lower()
        direction_buy = 1.0 if direction == 'buy' else 0.0
        
        # Profit (target)
        profit = float(row['profit'])
        is_win = 1.0 if profit > 0 else 0.0
        
        # Prices
        entry = float(row['opening_price'])
        sl = float(row['stop_loss']) if row.get('stop_loss') else 0
        tp = float(row['take_profit']) if row.get('take_profit') else 0
        
        # SL/TP distance in pips (approximate)
        if entry > 0:
            if 'JPY' in symbol:
                sl_pips = abs(entry - sl) * 100
                tp_pips = abs(tp - entry) * 100
            elif 'XAU' in symbol or 'XAG' in symbol:
                sl_pips = abs(entry - sl) * 10
                tp_pips = abs(tp - entry) * 10
            elif 'BTC' in symbol or 'ETH' in symbol:
                sl_pips = abs(entry - sl)
                tp_pips = abs(tp - entry)
            else:
                sl_pips = abs(entry - sl) * 10000
                tp_pips = abs(tp - entry) * 10000
        else:
            sl_pips = 50.0
            tp_pips = 125.0
        
        rr_ratio = tp_pips / max(sl_pips, 1.0)
        
        # Cyclical hour encoding
        hour_sin = np.sin(2 * np.pi * hour_utc / 24)
        hour_cos = np.cos(2 * np.pi * hour_utc / 24)
        
        # Symbol one-hot
        sym_features = _encode_symbol(symbol)
        
        # Build feature vector
        features = {
            'hour_sin': hour_sin,
            'hour_cos': hour_cos,
            'day_of_week': day_of_week / 6.0,
            'rsi': 0.5,  # Placeholder — will be enriched later
            'macd_hist': 0.0,
            'ma_short_above_long': 0.5,
            'volatility_pct': 0.1,
            'atr_pct': 0.1,
            'direction_buy': direction_buy,
            'sl_distance_pips': np.clip(sl_pips, 5, 500) / 500.0,
            'tp_distance_pips': np.clip(tp_pips, 5, 1000) / 1000.0,
            'rr_ratio': np.clip(rr_ratio, 0, 5) / 5.0,
            'signal_strength': 0.5,
        }
        features.update(sym_features)
        
        X = [features.get(name, 0.0) for name in FEATURE_NAMES]
        return {'X': X, 'y': is_win, 'symbol': symbol, 'profit': profit}
    except Exception as e:
        return None


def train_from_csvs(csv_paths: list) -> dict:
    """Train the ML model from CSV trade history files.
    
    Args:
        csv_paths: List of paths to MT5 history CSV files
        
    Returns:
        Training metrics dict
    """
    from sklearn.ensemble import GradientBoostingClassifier
    from sklearn.model_selection import train_test_split
    from sklearn.metrics import accuracy_score, precision_score, recall_score, f1_score
    import joblib
    
    # Parse all trades
    all_trades = []
    for path in csv_paths:
        if not os.path.exists(path):
            logger.warning(f"File not found: {path}")
            continue
        with open(path, 'r', encoding='utf-8') as f:
            reader = csv.DictReader(f)
            for row in reader:
                parsed = _parse_trade_row(row)
                if parsed:
                    all_trades.append(parsed)
    
    if len(all_trades) < 50:
        logger.error(f"Not enough trades to train (need 50+, got {len(all_trades)})")
        return {'success': False, 'error': 'Not enough data'}
    
    logger.info(f"Parsed {len(all_trades)} trades from {len(csv_paths)} file(s)")
    
    # Prepare data
    X = np.array([t['X'] for t in all_trades])
    y = np.array([t['y'] for t in all_trades])
    
    # Split
    X_train, X_test, y_train, y_test = train_test_split(
        X, y, test_size=0.2, random_state=42, stratify=y
    )
    
    logger.info(f"Training set: {len(X_train)}, Test set: {len(X_test)}")
    logger.info(f"Win rate: {y.mean()*100:.1f}%")
    
    # Train model
    model = GradientBoostingClassifier(
        n_estimators=100,
        max_depth=4,
        learning_rate=0.1,
        random_state=42,
        subsample=0.8,
    )
    model.fit(X_train, y_train)
    
    # Evaluate
    y_pred = model.predict(X_test)
    y_proba = model.predict_proba(X_test)[:, 1]
    
    metrics = {
        'success': True,
        'total_trades': len(all_trades),
        'train_size': len(X_train),
        'test_size': len(X_test),
        'win_rate': float(y.mean() * 100),
        'accuracy': float(accuracy_score(y_test, y_pred) * 100),
        'precision': float(precision_score(y_test, y_pred, zero_division=0) * 100),
        'recall': float(recall_score(y_test, y_pred, zero_division=0) * 100),
        'f1_score': float(f1_score(y_test, y_pred, zero_division=0) * 100),
    }
    
    # Feature importance
    importances = model.feature_importances_
    feature_imp = sorted(
        zip(FEATURE_NAMES, importances),
        key=lambda x: x[1], reverse=True
    )
    metrics['feature_importance'] = {name: round(float(imp), 4) for name, imp in feature_imp}
    
    logger.info(f"Model accuracy: {metrics['accuracy']:.1f}%")
    logger.info(f"F1 score: {metrics['f1_score']:.1f}%")
    logger.info(f"Top features: {feature_imp[:5]}")
    
    # Save model
    os.makedirs(MODEL_DIR, exist_ok=True)
    joblib.dump(model, MODEL_PATH)
    logger.info(f"Model saved to {MODEL_PATH}")
    
    # Save metadata
    metadata = {
        'trained_at': datetime.now().isoformat(),
        'total_trades': len(all_trades),
        'accuracy': metrics['accuracy'],
        'win_rate': metrics['win_rate'],
        'feature_importance': metrics['feature_importance'],
    }
    with open(METADATA_PATH, 'w') as f:
        json.dump(metadata, f, indent=2)
    logger.info(f"Metadata saved to {METADATA_PATH}")
    
    return metrics


def main():
    """Train from all available history files."""
    history_dir = os.path.join(os.path.dirname(__file__), 'History')
    
    # Find all MT5 history CSVs
    csv_files = []
    for fname in os.listdir(history_dir):
        if fname.endswith('.csv') and 'binance' not in fname.lower() and 'tradinglog' not in fname.lower():
            csv_files.append(os.path.join(history_dir, fname))
    
    if not csv_files:
        logger.error("No trade history CSVs found in History/")
        return
    
    logger.info(f"Found {len(csv_files)} trade history files:")
    for f in csv_files:
        logger.info(f"  {os.path.basename(f)}")
    
    metrics = train_from_csvs(csv_files)
    
    if metrics.get('success'):
        logger.info("\n" + "="*50)
        logger.info("TRAINING COMPLETE")
        logger.info(f"Accuracy: {metrics['accuracy']:.1f}%")
        logger.info(f"Win rate: {metrics['win_rate']:.1f}%")
        logger.info(f"F1 Score: {metrics['f1_score']:.1f}%")
        logger.info("="*50)
    else:
        logger.error(f"Training failed: {metrics.get('error')}")


if __name__ == '__main__':
    main()

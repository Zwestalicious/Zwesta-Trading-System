import time
from typing import Dict, List, Optional

_ml_pipeline = None
_ml_exit_predictor = None
_regime_cache = {}
_regime_ttl = 60.0
_ml_eval_cache = {}
_ml_cache_ttl = 2.0


def init_engine():
    global _ml_pipeline, _ml_exit_predictor
    from ml_pipeline import get_ml_pipeline
    from ml_exit_manager import get_exit_predictor
    _ml_pipeline = get_ml_pipeline()
    _ml_exit_predictor = get_exit_predictor()
    print(f"[ENGINE] ML Ready | Pipeline: {_ml_pipeline is not None}")


def process_tick_optimized(
    symbol: str,
    market_data: Dict,
    bot_config: Dict,
    existing_positions: List[Dict],
    broker_name: str,
) -> Optional[Dict]:
    t_start = time.perf_counter()

    if not bot_config.get("enabled", True):
        return None

    regime = _get_cached_regime(symbol, market_data)
    if regime == "CHOP_HIGH_VOL":
        if market_data.get("strength", 0) < 75:
            return None

    for pos in existing_positions:
        if pos.get("symbol") == symbol:
            return None

    if not _check_broker_limits_fast(bot_config, symbol, broker_name):
        return None

    raw_signal = run_strategy_fast(symbol, market_data, bot_config)
    if not raw_signal or raw_signal.get("signal") in ("HOLD", None, ""):
        return None

    strength = float(raw_signal.get("strength", 0))
    threshold = _get_adaptive_threshold(bot_config, regime)
    if strength < threshold:
        if strength < (threshold - 10):
            return None
        if not _try_ml_override(symbol, market_data, raw_signal, bot_config, threshold):
            return None

    position_size = _calc_base_volume(symbol, bot_config, broker_name, market_data)
    if position_size <= 0:
        return None

    position_size = _apply_ml_sizing_cached(
        symbol, market_data, position_size, existing_positions, bot_config
    )
    if position_size <= 0:
        return None

    throttle = _get_drawdown_throttle_cached(bot_config)
    position_size *= throttle

    final_volume = _calc_broker_volume(
        broker_name, symbol, position_size, bot_config, market_data
    )

    return {
        "symbol": symbol,
        "type": raw_signal.get("signal"),
        "volume": final_volume,
        "raw_strength": strength,
        "regime": regime,
        "entry_reason": raw_signal.get("entry_reason", ""),
        "processing_ms": (time.perf_counter() - t_start) * 1000,
    }


def process_exits_batch(open_positions: Dict, market_data_map: Dict, bot_config: Dict) -> List[Dict]:
    actions = []
    for ticket, tracked in open_positions.items():
        symbol = tracked.get("symbol")
        mdata = market_data_map.get(symbol)
        if not mdata:
            continue

        profit = float(tracked.get("profit", 0))
        if profit <= 0 and float(tracked.get("peakProfit", 0)) <= 0:
            if profit > -20:
                continue

        reason = _ml_exit_evaluate_cached(symbol, tracked, mdata, bot_config)
        if reason:
            actions.append({"ticket": ticket, "symbol": symbol, "reason": reason})
    return actions


def _get_cached_regime(symbol: str, market_data: Dict) -> str:
    now = time.time()
    if symbol in _regime_cache:
        ts, regime = _regime_cache[symbol]
        if now - ts < _regime_ttl:
            return regime
    regime = market_data.get("regime", "TREND")
    _regime_cache[symbol] = (now, regime)
    return regime


def _apply_ml_sizing_cached(symbol, market_data, position_size, existing_positions, bot_config):
    if not _ml_pipeline:
        return position_size
    cache_key = f"{symbol}:{market_data.get('close',0)}"
    now = time.time()
    if cache_key in _ml_eval_cache:
        ts, mult = _ml_eval_cache[cache_key]
        if now - ts < _ml_cache_ttl:
            return position_size * mult

    try:
        existing_syms = [p.get("symbol", "") for p in (existing_positions or [])]
        ml_eval = _ml_pipeline.evaluate_entry(symbol, market_data, {"signal": "BUY"}, existing_syms)
        if not ml_eval.get("should_trade", True):
            return 0.0
        mult = float(ml_eval.get("position_size", {}).get("size_multiplier", 1.0) or 1.0)
        mult = max(0.3, min(mult, 2.0))
        _ml_eval_cache[cache_key] = (now, mult)
        return position_size * mult
    except Exception:
        return position_size


def _get_drawdown_throttle_cached(bot_config):
    if not _ml_pipeline or not getattr(_ml_pipeline, "anomaly", None):
        return 1.0
    history = getattr(_ml_pipeline.anomaly, "win_history", []) or []
    if len(history) < 20:
        return 1.0
    recent = history[-50:]
    win_rate = sum(1 for r in recent if r.get("actual")) / len(recent)
    if win_rate < 0.35:
        return 0.4
    if win_rate < 0.45:
        return 0.7
    if win_rate > 0.6:
        return 1.1
    return 1.0


def _get_adaptive_threshold(bot_config, regime):
    base = 65
    if regime == "CHOP_HIGH_VOL":
        base += 10
    elif "TREND" in regime:
        base -= 5
    return base


def _check_broker_limits_fast(bot_config, symbol, broker_name):
    return True


def _try_ml_override(symbol, market_data, raw_signal, bot_config, threshold):
    if not _ml_pipeline:
        return False
    try:
        eval_result = _ml_pipeline.evaluate_entry(symbol, market_data, raw_signal, [])
        conf = float(eval_result.get("confidence", 0))
        return conf > 0.78
    except Exception:
        return False


def run_strategy_fast(symbol, market_data, bot_config):
    try:
        from multi_broker_backend_updated import evaluate_real_trade_signal
        return evaluate_real_trade_signal(symbol, market_data)
    except Exception:
        return None


def _calc_base_volume(symbol, bot_config, broker_name, market_data):
    try:
        return float(bot_config.get("fixed_lot", 0.01))
    except Exception:
        return 0.01


def _calc_broker_volume(broker_name, symbol, size, bot_config, market_data):
    try:
        if "Exness" in str(broker_name):
            return min(size, float(bot_config.get("symbol_cap", 5.0)))
        return size
    except Exception:
        return size


def _ml_exit_evaluate_cached(symbol, tracked, market_data, bot_config):
    if not _ml_exit_predictor or not getattr(_ml_exit_predictor, "is_ready", False):
        return None
    try:
        profit = float(tracked.get("profit", 0))
        peak = float(tracked.get("peakProfit", 0))
        pred = _ml_exit_predictor.predict_exit(
            symbol=symbol,
            direction=str(tracked.get("type", "buy")).upper(),
            current_pnl=profit,
            peak_pnl=peak,
            entry_time=str(tracked.get("entryTime", "")),
            current_rsi=market_data.get("rsi", 50),
            current_macd=market_data.get("macd_hist", 0),
            volatility_pct=market_data.get("volatility_pct", 1.0),
            distance_to_tp_pips=float(tracked.get("takeProfitPips", 100)),
            distance_from_sl_pips=float(tracked.get("stopLossPips", 50)),
            consecutive_bars=5,
            spread_pct=0.01,
        )
        if float(pred.get("confidence", 0)) < 0.68:
            return None
        return {
            "CLOSE_FULL": "EXIT_ML_FULL",
            "CLOSE_PARTIAL": "EXIT_ML_PARTIAL",
        }.get(pred.get("action", ""), None)
    except Exception:
        return None

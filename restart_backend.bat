#!/bin/bash
export PYTHONIOENCODING=utf-8
export ZWESTA_SKIP_PYTHON_REEXEC=1
export MT5_STARTUP_WARMUP=0
export PYTHONUNBUFFERED=1
.venv\Scripts\python.exe -u multi_broker_backend_updated.py

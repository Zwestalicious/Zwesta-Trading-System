@echo off
set PYTHONIOENCODING=utf-8
set ZWESTA_SKIP_PYTHON_REEXEC=1
set MT5_STARTUP_WARMUP=0
set PYTHONUNBUFFERED=1
cd /d "C:\zwesta-trader\Zwesta Flutter App"
start /b "" ".venv\Scripts\python.exe" -u "multi_broker_backend_updated.py"

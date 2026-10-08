"""Hermes entry point; the adapter lives in adapters/hermes/plugin.py."""
import importlib.util
from pathlib import Path

_spec = importlib.util.spec_from_file_location(
    "robotspeak_hermes", Path(__file__).resolve().parent / "adapters" / "hermes" / "plugin.py")
_adapter = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_adapter)
register = _adapter.register

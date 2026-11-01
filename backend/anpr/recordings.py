"""Fixed prototype sources and one synchronous recorded-processing slot.

The slot is process-local. Run this prototype with one FastAPI worker; it is
not a distributed job queue. Database RPCs remain the admission authority.
"""
from contextlib import contextmanager
from datetime import datetime, timezone
from hashlib import sha256
from functools import lru_cache
from pathlib import Path
from threading import Lock

from fastapi import HTTPException

RECORDINGS = Path(__file__).resolve().parents[2] / 'data' / 'videos'
ENTRANCE_RECORDING = RECORDINGS / 'inti_entrance.mp4'
EXIT_RECORDING = RECORDINGS / 'inti_exit.mp4'
SOURCES = {'entrance': ENTRANCE_RECORDING, 'exit': EXIT_RECORDING}
_lock = Lock()
_state_lock = Lock()
_active = None


def source(role):
    if role not in SOURCES:
        raise HTTPException(404, 'Camera not found.')
    return SOURCES[role]


def identity(path):
    digest = sha256()
    try:
        with path.open('rb') as stream:
            for chunk in iter(lambda: stream.read(1024 * 1024), b''):
                digest.update(chunk)
    except OSError:
        raise HTTPException(503, 'The configured recording is unavailable.') from None
    return digest.hexdigest()


def metadata_identity(path):
    """Cache display metadata only. Processing still hashes the actual footage."""
    try:
        stat = path.stat()
        key = (stat.st_dev, stat.st_ino, stat.st_size, stat.st_mtime_ns, stat.st_ctime_ns)
        return _metadata_identity(path, key)
    except OSError:
        raise HTTPException(503, 'The configured recording is unavailable.') from None


@lru_cache(maxsize=8)
def _metadata_identity(path, key):
    digest = identity(path)
    stat = path.stat()
    if key != (stat.st_dev, stat.st_ino, stat.st_size, stat.st_mtime_ns, stat.st_ctime_ns):
        raise HTTPException(503, 'The recording changed. Refresh its metadata.')
    return digest


def active_run():
    with _state_lock:
        return dict(_active) if _active else None


@contextmanager
def processing_slot(role, playback_id):
    global _active
    if not _lock.acquire(blocking=False):
        raise HTTPException(409, {'code': 'processing_busy',
                                 'message': 'Recorded processing is already running. Wait for its outcome before retrying.'})
    with _state_lock:
        _active = dict(role=role, playback_id=str(playback_id),
                       started_at=datetime.now(timezone.utc).isoformat())
    try:
        yield
    finally:
        with _state_lock:
            _active = None
        _lock.release()

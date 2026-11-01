"""Pure recognition validation. Never repairs identity or clamps timestamps."""
from datetime import datetime, timezone
import math
import re


def invalid_fields(event, *, now=None, check_future=True):
    """Return fixed field labels only; never include submitted values.

    These are application checks, not a claim about the database clock. SQL
    remains the authority for acceptance and playback-start comparisons.
    """
    issues = []
    identity = getattr(event, 'event_id', None)
    if not isinstance(identity, str) or not identity.strip() or len(identity) > 256:
        issues.append('event_id')
    plate = getattr(event, 'plate_number', None)
    if not isinstance(plate, str) or re.fullmatch(r'[A-Z0-9]{1,32}', plate) is None:
        issues.append('plate_number')
    camera = getattr(event, 'camera_id', None)
    if not isinstance(camera, str) or not 1 <= len(camera.strip(' ')) <= 100:
        issues.append('camera_id')
    if getattr(event, 'camera_role', None) not in ('entrance', 'exit'):
        issues.append('camera_role')
    stamp = getattr(event, 'timestamp', None)
    try:
        valid_time = (isinstance(stamp, datetime) and stamp.tzinfo is not None
                      and stamp.utcoffset() is not None)
        if not valid_time:
            issues.append('event_time')
        else:
            stamp.astimezone(timezone.utc)
            if check_future and stamp > (now or datetime.now(timezone.utc)):
                issues.append('event_time_future_application')
    except (ValueError, TypeError, OverflowError):
        issues.append('event_time')
    offset = getattr(event, 'source_time_seconds', None)
    if offset is not None and (type(offset) not in (int, float)
            or not math.isfinite(offset) or not 0 <= offset <= 999999999.999):
        issues.append('source_time_seconds')
    return tuple(issues)

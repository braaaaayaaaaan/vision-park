from dataclasses import dataclass
from datetime import datetime


@dataclass(frozen=True)
class RecognitionEvent:
    """ANPR confirmation, not registration verification or access approval.

    timestamp is the UTC processing/confirmation time. source_time_seconds is
    the confirming frame's offset in a recorded file, or None when unavailable.
    """

    plate_number: str
    timestamp: datetime
    camera_id: str
    camera_role: str
    event_id: str
    source_time_seconds: float | None = None

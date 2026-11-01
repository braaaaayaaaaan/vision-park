import cv2
from math import isfinite
from pathlib import Path
from threading import Event
from typing import Iterator


class Camera:
    """Read frames from a recorded file, webcam, or stream in the owning worker."""

    def __init__(self, source):
        self.source = source
        self.capture = None
        self.source_time_seconds: float | None = None

    def open(self) -> None:
        self.capture = cv2.VideoCapture(self.source)
        if not self.capture.isOpened():
            self.release()
            raise RuntimeError(f"Unable to open the video source: {self.source}")

    def frames(self, stop_event: Event | None = None) -> Iterator:
        try:
            if self.capture is None:
                self.open()
            is_recording = isinstance(self.source, str) and Path(self.source).is_file()
            fps = self.capture.get(cv2.CAP_PROP_FPS)
            expected_frames = self.capture.get(cv2.CAP_PROP_FRAME_COUNT) if is_recording else 0
            frame_index = 0
            while stop_event is None or not stop_event.is_set():
                success, frame = self.capture.read()
                if not success:
                    if isfinite(expected_frames) and frame_index < expected_frames - .5:
                        raise RuntimeError('The recording ended before all reported frames were decoded')
                    break
                self.source_time_seconds = None
                if is_recording:
                    offset = self.capture.get(cv2.CAP_PROP_POS_MSEC) / 1000
                    if isfinite(offset) and (offset > 0 or frame_index == 0):
                        self.source_time_seconds = max(0.0, offset)
                    elif isfinite(fps) and fps > 0:
                        self.source_time_seconds = frame_index / fps
                frame_index += 1
                yield frame
        finally:
            self.release()

    def release(self) -> None:
        if self.capture is not None:
            self.capture.release()
            self.capture = None

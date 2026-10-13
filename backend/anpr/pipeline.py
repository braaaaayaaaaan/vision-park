from contextlib import closing
from datetime import datetime, timezone
from threading import Event
from typing import Iterator
from uuid import uuid4

from backend.anpr.camera import Camera
from backend.anpr.vehicle_tracker import VehicleTracker
from backend.anpr.plate_detector import PlateDetector
from backend.anpr.ocr import OCR
from backend.anpr.plate_processor import PlateProcessor
from backend.anpr.plate_recognition_manager import PlateRecognitionManager
from backend.anpr.events import RecognitionEvent


class ANPRPipeline:
    """One source run; construct a fresh pipeline to replay/reset tracking."""

    def __init__(self, source, vehicle_model_path: str = "models/vehicle/yolo26s.pt",
                 plate_model_path: str = "models/plate/best.pt",
                 vehicle_confidence: float = 0.5, plate_confidence: float = 0.5, *,
                 camera_id: str, camera_role: str,
                 minimum_observations: int = 5, confirmation_ratio: float = 0.6,
                 minimum_ocr_confidence: float = 0.85, maximum_observations: int = 10):
        if not camera_id.strip():
            raise ValueError("camera_id must not be blank")
        if camera_role not in {"entrance", "exit"}:
            raise ValueError("camera_role must be entrance or exit")
        self.camera_id = camera_id
        self.camera_role = camera_role
        self._stop_event = Event()
        self._has_run = False
        self.plate_recognition_manager = PlateRecognitionManager(
            minimum_observations, confirmation_ratio,
            minimum_ocr_confidence, maximum_observations,
        )
        self.camera = Camera(source)
        self.vehicle_tracker = VehicleTracker(vehicle_model_path, vehicle_confidence)
        self.plate_detector = PlateDetector(plate_model_path, plate_confidence)
        self.ocr = OCR()
        self.plate_processor = PlateProcessor(self.plate_detector, self.ocr)

    def run(self) -> Iterator[RecognitionEvent]:
        if self._has_run:
            raise RuntimeError("Create a fresh ANPRPipeline for another source run")
        self._has_run = True
        try:
            with closing(self.camera.frames(self._stop_event)) as frames:
                for frame_index, frame in enumerate(frames):
                    if self._stop_event.is_set():
                        break
                    vehicles = self.vehicle_tracker.update(frame)
                    self.plate_recognition_manager.retain_tracks(
                        self.vehicle_tracker.retained_track_ids()
                    )
                    seen_tracks = set()
                    for vehicle in vehicles:
                        if self._stop_event.is_set():
                            break
                        if vehicle.track_id in seen_tracks:
                            continue
                        seen_tracks.add(vehicle.track_id)
                        if self.plate_recognition_manager.is_confirmed(vehicle.track_id):
                            continue
                        results = self.plate_processor.process(frame, vehicle)
                        plate = self.plate_recognition_manager.observe_frame(
                            vehicle.track_id, frame_index, results
                        )
                        if plate is not None and not self._stop_event.is_set():
                            yield RecognitionEvent(
                                plate_number=plate,
                                timestamp=datetime.now(timezone.utc),
                                camera_id=self.camera_id,
                                camera_role=self.camera_role,
                                event_id=str(uuid4()),
                                source_time_seconds=self.camera.source_time_seconds,
                            )
        finally:
            self.camera.release()
            self.plate_recognition_manager.clear()

    def stop(self) -> None:
        # Only the worker owns capture.release(); cancellation is cooperative.
        self._stop_event.set()

from ultralytics import YOLO
from dataclasses import dataclass
from typing import List, Tuple

@dataclass
class TrackedVehicle:
    """
    represents the metadata of detecting and tracking the 
    vehicle across frames
    """

    track_id: int
    bbox: Tuple[int, int, int, int]
    confidence: float
    class_id: int
    class_name: str

class VehicleTracker:
    """
    detects and tracks various types of vehicles using
    yolo26 model and ByteTrack tracking algorithm
    """

    VEHICLE_CLASS_NAMES = frozenset({"car", "motorcycle", "bus", "truck"})

    def __init__(self, model_path: str = "models/vehicle/yolo26s_vehicle_finetuned.pt", confidence_threshold: float = 0.5):
        self.model_path = model_path
        self.confidence_threshold = confidence_threshold
        self.reset()

    def update(self, frame):
        results = self.model.track(
            source=frame, 
            conf=self.confidence_threshold,
            tracker="bytetrack.yaml",
            persist=True,
            verbose=False
        )

        tracked_vehicles: List[TrackedVehicle] = []

        for result in results:
            if result.boxes is None:
                continue

            if result.boxes.id is None:
                continue

            for box, track_id in zip(result.boxes, result.boxes.id):
                class_id = int(box.cls[0])

                if class_id not in self.vehicle_classes:
                    continue

                confidence = float(box.conf[0])

                x1,y1,x2,y2 = box.xyxy[0].tolist()

                tracked_vehicle = TrackedVehicle(
                    track_id=int(track_id),
                    bbox=(
                        int(x1),
                        int(y1),
                        int(x2),
                        int(y2),
                    ),
                    confidence=confidence,
                    class_id=class_id,
                    class_name=self.vehicle_classes[class_id]
                )

                tracked_vehicles.append(tracked_vehicle)

        return tracked_vehicles

    def retained_track_ids(self) -> set[int]:
        """Keep active and temporarily lost ByteTrack IDs until retirement."""
        predictor = self.model.predictor
        if predictor is None or not hasattr(predictor, "trackers"):
            raise RuntimeError("ByteTrack has not been initialised by update()")
        return {
            track.track_id
            for tracker in predictor.trackers
            for track in (*tracker.tracked_stracks, *tracker.lost_stracks)
        }

    def reset(self) -> None:
        model = YOLO(self.model_path)
        vehicle_classes = {}
        matched_names = set()
        for class_id, label in model.names.items():
            name = label.strip().casefold()
            if name not in self.VEHICLE_CLASS_NAMES:
                continue
            if name in matched_names:
                raise ValueError(f"{self.model_path}: ambiguous vehicle class {name!r}")
            vehicle_classes[class_id] = name
            matched_names.add(name)
        missing_names = self.VEHICLE_CLASS_NAMES - matched_names
        if missing_names:
            raise ValueError(
                f"{self.model_path}: missing vehicle classes: {', '.join(sorted(missing_names))}"
            )
        self.model = model
        self.vehicle_classes = vehicle_classes

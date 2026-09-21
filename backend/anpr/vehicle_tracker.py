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

    #note: for now, let's keep it this way huh 
    VEHICLE_CLASSES = {
        2: "car",
        3: "motorcycle",
        5: "bus",
        7: "truck"
    }

    def __init__(self, model_path: str = "models/vehicle/yolo26s.pt", confidence_threshold: float = 0.5):
        self.model_path = model_path
        self.model = YOLO(model_path)
        self.confidence_threshold = confidence_threshold
        self.vehicle_classes = self.VEHICLE_CLASSES

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

    def reset(self) -> None:
        self.model = YOLO(self.model_path)
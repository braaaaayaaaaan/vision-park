from ultralytics import YOLO
from dataclasses import dataclass
from typing import List, Tuple

#note: the whole point of using dataclass is
#to have a structured representation of the metadata 
@dataclass
class VehicleDetection:
    """
    represents the metadata of a detected vehicle type
    """

    bbox: Tuple[int, int, int, int]
    confidence: float
    class_id: int
    class_name: str

class VehicleDetector:
    """
    detects vehicle in video frames from relevant sources
    """

    #todo: remove or change when necessary (now just testing)
    VEHICLE_CLASSES = {
        2: "car",
        3: "motorcycle",
        5: "bus",
        7: "truck"
    }

    def __init__(self, model_path: str = "models/vehicle/yolo26s.pt", confidence_threshold: float = 0.5):
        self.model = YOLO(model_path)
        self.confidence_threshold = confidence_threshold

        self.vehicle_classes = self.VEHICLE_CLASSES

    def detect(self, frame) -> List[VehicleDetection]:
        results = self.model.predict(
            source=frame,
            conf=self.confidence_threshold,
            verbose=False,
        )

        detections: List[VehicleDetection] = []

        for result in results:
            if result.boxes is None:
                continue

            for box in result.boxes:
                class_id = int(box.cls[0])
                confidence = float(box.conf[0])

                if class_id not in self.vehicle_classes:
                    continue

                x1, y1, x2, y2 = box.xyxy[0].tolist()

                detection = VehicleDetection(
                    bbox=(
                        int(x1),
                        int(y1),
                        int(x2),
                        int(y2),
                    ),
                    confidence=confidence,
                    class_id=class_id,
                    class_name=self.vehicle_classes[class_id],
                )

                detections.append(detection)

        return detections
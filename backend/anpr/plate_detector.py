from ultralytics import YOLO
from dataclasses import dataclass
from typing import List, Tuple

@dataclass
class PlateDetection:
    """
    represents the metadata of the detected number plate
    """

    bbox: Tuple[int, int, int, int]
    confidence: float

class PlateDetector:
    """
    detects the number plates within the vehicle images
    """

    #note: for now this stays the same until i fine-tune the plate detector
    PLATE_CLASS_ID = 0
    PLATE_CLASS_NAME = "plate"

    def __init__(self, model_path: str = "models/plate/best.pt", confidence_threshold: float = 0.5):
        self.model = YOLO(model_path)
        self.confidence_threshold = confidence_threshold

    def detect(self, vehicle_image) -> List[PlateDetection]:
        results = self.model.predict(
            source=vehicle_image,
            conf=self.confidence_threshold,
            verbose=False,
        )

        plates: List[PlateDetection] = []

        for result in results:
            if result.boxes is None:
                continue

            for box in result.boxes:
                class_id = int(box.cls[0])

                if class_id != self.PLATE_CLASS_ID:
                    continue

                confidence = float(box.conf[0])

                x1,y1,x2,y2 = box.xyxy[0].tolist()

                plate = PlateDetection(
                    bbox=(
                        int(x1),
                        int(y1),
                        int(x2),
                        int(y2),
                    ),
                    confidence=confidence
                )

                plates.append(plate)

        return plates
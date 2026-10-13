from __future__ import annotations

from dataclasses import dataclass
from typing import List, TYPE_CHECKING

if TYPE_CHECKING:
    from backend.anpr.vehicle_tracker import TrackedVehicle
    from backend.anpr.plate_detector import PlateDetector
    from backend.anpr.ocr import OCR

@dataclass
class ProcessedPlate:
    """
    represents the information on the processed number plates
    """

    track_id: int
    vehicle_class: str
    vehicle_confidence: float

    plate_bbox: tuple[int, int, int, int]
    plate_confidence: float

    text: str
    ocr_confidence: float

class PlateProcessor:
    """
    performs the heavy processing for the entire pipeline
    """

    def __init__(self, plate_detector: PlateDetector, ocr: OCR):
        self.plate_detector = plate_detector
        self.ocr = ocr

    def process(self, frame, vehicle: TrackedVehicle) -> List[ProcessedPlate]:
        # perform vehicle cropping from the original frame
        vehicle_crop = self._crop_image(image=frame, bbox=vehicle.bbox)

        if vehicle_crop is None:
            return []

        plate_detections = self.plate_detector.detect(vehicle_crop)
        processed_plates: List[ProcessedPlate] = []

        for plate in plate_detections:
            plate_crop = self._crop_image(image=vehicle_crop, bbox=plate.bbox)

            if plate_crop is None:
                continue

            ocr_result = self.ocr.recognise(plate_crop)

            if ocr_result is None:
                continue

            processed_plate = ProcessedPlate(
                track_id=vehicle.track_id,
                vehicle_class=vehicle.class_name,
                vehicle_confidence=vehicle.confidence,
                plate_bbox=plate.bbox,
                plate_confidence=plate.confidence,
                text=ocr_result.text,
                ocr_confidence=ocr_result.confidence
            )

            processed_plates.append(processed_plate)

        return processed_plates

    @staticmethod
    def _crop_image(image, bbox: tuple[int, int, int, int]):
        """
        perform cropping in the format (x1,y1,x2,y2)
        """

        height, width = image.shape[:2]
        x1, y1, x2, y2 = bbox

        x1 = max(0, min(x1, width))
        y1 = max(0, min(y1, height))
        x2 = max(0, min(x2, width))
        y2 = max(0, min(y2, height))

        if x2 <= x1 or y2 <= y1:
            return None

        return image[y1:y2, x1:x2]

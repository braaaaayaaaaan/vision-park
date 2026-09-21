from typing import Iterator

from backend.anpr.camera import Camera
from backend.anpr.vehicle_tracker import VehicleTracker
from backend.anpr.plate_detector import PlateDetector
from backend.anpr.ocr import OCR
from backend.anpr.plate_processor import PlateProcessor, ProcessedPlate

#note: testing out the optimisation script (can remove if the performance is not good)
from backend.anpr.plate_recognition_manager import PlateRecognitionManager

class ANPRPipeline:
    def __init__(self, source, vehicle_model_path: str = "models/vehicle/yolo26s.pt", plate_model_path: str = "models/plate/best.pt",
                 vehicle_confidence: float = 0.5, plate_confidence: float = 0.5):
        
        self.camera = Camera(source)

        self.vehicle_tracker = VehicleTracker(model_path=vehicle_model_path, confidence_threshold=vehicle_confidence)

        self.plate_detector = PlateDetector(model_path=plate_model_path, confidence_threshold=plate_confidence)

        self.ocr = OCR()

        self.plate_processor = PlateProcessor(plate_detector=self.plate_detector, ocr=self.ocr)

        #note: remove optimisation part if needed
        self.plate_recognition_manager = PlateRecognitionManager(
            minimum_observations=5,
            confirmation_ratio=0.6,
            minimum_ocr_confidence=0.85,
            maximum_observations=10,
        )

    def run(self) -> Iterator[ProcessedPlate]:
        try:
            for frame in self.camera.frames():
                #note: can remove this optimisation thing
                vehicles = self.vehicle_tracker.update(frame)

                for vehicle in vehicles:
                    if self.plate_recognition_manager.is_confirmed(vehicle.track_id):
                        continue
                    
                    results = self.plate_processor.process(frame=frame, vehicle=vehicle)

                    for result in results:
                        confirmed_plate = self.plate_recognition_manager.observe(result)

                        if confirmed_plate is not None:
                            result.text = confirmed_plate
                            yield result
        finally:
            self.camera.release()

    def stop(self) -> None:
        self.camera.release()
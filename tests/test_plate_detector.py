from backend.anpr.plate_detector import PlateDetector

detector = PlateDetector()

plates = detector.detect("data/images/image_1.jpeg")

for plate in plates:
    print(
        f"Confidence: {plate.confidence:.2f} | "
        f"BBox: {plate.bbox}"
    )
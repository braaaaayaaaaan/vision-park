from backend.anpr.pipeline import ANPRPipeline

def main():
    pipeline = ANPRPipeline(source="data/videos/video_10.mp4")

    for result in pipeline.run():
        print(
            f"Vehicle ID: {result.track_id} | "
            f"Vehicle: {result.vehicle_class} | "
            f"Vehicle Confidence: {result.vehicle_confidence:.2f} | "
            f"Plate: {result.text} | "
            f"Plate Confidence: {result.plate_confidence} | "
            f"OCR Confidence: {result.ocr_confidence:.2f} | "
        )

if __name__ == "__main__":
    main()
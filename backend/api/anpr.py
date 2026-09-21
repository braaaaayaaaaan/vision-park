from fastapi import APIRouter
from backend.anpr.pipeline import ANPRPipeline

router = APIRouter()

@router.get("/test")
def test_anpr():
    pipeline = ANPRPipeline(source="data/videos/video_10.mp4")

    results = []

    for result in pipeline.run():
        results.append({
            "vehicle_id": result.track_id,
            "vehicle_class": result.vehicle_class,
            "vehicle_confidence": result.vehicle_confidence,
            "plate": result.text,
            "plate_confidence": result.plate_confidence,
            "ocr_confidence": result.ocr_confidence
        })

    return {"results": results}
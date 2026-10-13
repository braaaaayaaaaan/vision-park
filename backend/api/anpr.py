from dataclasses import asdict

from fastapi import APIRouter
from backend.anpr.pipeline import ANPRPipeline

router = APIRouter()


@router.get("/test")
def test_anpr():
    pipeline = ANPRPipeline(
        source="data/videos/entrance.mp4",
        camera_id="test-entrance",
        camera_role="entrance",
    )
    return {"results": [asdict(event) for event in pipeline.run()]}

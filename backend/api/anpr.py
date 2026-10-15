from dataclasses import asdict
from contextlib import closing
from uuid import UUID

from fastapi import APIRouter, Depends
from pydantic import BaseModel, ConfigDict
from backend.anpr.pipeline import ANPRPipeline
from backend.api.parking import require_allocation_access
from backend.parking.entrance import EntranceEventHandler

router = APIRouter()


@router.get("/test")
def test_anpr():
    pipeline = ANPRPipeline(
        source="data/videos/inti_ramp.mp4",
        camera_id="test-entrance",
        camera_role="entrance",
    )
    return {"results": [asdict(event) for event in pipeline.run()]}


class EntranceRunRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")
    entrance_node_id: UUID


@router.post("/entrance", dependencies=[Depends(require_allocation_access)])
def run_entrance(request: EntranceRunRequest):
    """Replay the entrance recording, allocating immediately on confirmation.

    This creates real reservations. The GET demo remains recognition-only.
    The caller explicitly maps this recording's camera to a building entrance.
    """
    handler = EntranceEventHandler({"recorded-entrance": str(request.entrance_node_id)})
    pipeline = ANPRPipeline(
        source="data/videos/entrance.mp4",
        camera_id="recorded-entrance", camera_role="entrance",
    )
    with closing(pipeline.run()) as events:
        return {"results": [handler(event) for event in events]}

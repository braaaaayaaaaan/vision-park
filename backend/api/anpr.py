from dataclasses import asdict
from contextlib import closing
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException
from fastapi.encoders import jsonable_encoder
from pydantic import BaseModel, ConfigDict
from backend.anpr.pipeline import ANPRPipeline
from backend.api.parking import require_allocation_access
from backend.parking.entrance import EntranceEventHandler
from backend.parking.exit import ExitEventHandler

router = APIRouter()


@router.get("/test")
def test_anpr():
    pipeline = ANPRPipeline(
        source="data/videos/inti_entrance.mp4",
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
        source="data/videos/inti_entrance.mp4",
        camera_id="recorded-entrance", camera_role="entrance",
    )
    with closing(pipeline.run()) as events:
        return {"results": [handler(event) for event in events]}


@router.post("/exit", dependencies=[Depends(require_allocation_access)])
def run_exit():
    """Replay the exit recording and close resolved sessions; no request body needed."""
    handler = ExitEventHandler({"recorded-exit"})
    results = []
    pipeline = None
    try:
        pipeline = ANPRPipeline(
            source="data/videos/inti_exit.mp4",
            camera_id="recorded-exit", camera_role="exit",
        )
        with closing(pipeline.run()) as events:
            for event in events:
                results.append(handler(event))
    except Exception:
        # Earlier closures may have committed. Preserve outcomes and never replay
        # automatically or expose raw model/capture exception details.
        raise HTTPException(503, jsonable_encoder({
            "code": "anpr_processing_failed",
            "message": "Exit processing failed; inspect results and resolved sessions before retrying.",
            "results": results,
        })) from None
    finally:
        if pipeline is not None:
            pipeline.stop()
    return {"results": results}

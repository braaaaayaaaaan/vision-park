import logging
from contextlib import closing
from dataclasses import asdict, dataclass
from threading import Thread, current_thread
from typing import Callable

from backend.anpr.events import RecognitionEvent
from backend.anpr.pipeline import ANPRPipeline

logger = logging.getLogger(__name__)


@dataclass(frozen=True)
class CameraConfig:
    camera_id: str
    camera_name: str
    camera_role: str
    source: str | int

    def __post_init__(self):
        if not self.camera_id.strip():
            raise ValueError("camera_id must not be blank")
        if self.camera_role not in {"entrance", "exit"}:
            raise ValueError("camera_role must be entrance or exit")


class CameraManager:
    """One independent pipeline per camera; call start/stop from the controller.

    Completed workers can be restarted. Workers that exceed the stop timeout
    remain registered, so start() never launches a replacement beside them.
    """

    def __init__(self, camera_configs: list[CameraConfig],
                 on_plate_confirmed: Callable[[RecognitionEvent], None] | None = None):
        if len({config.camera_id for config in camera_configs}) != len(camera_configs):
            raise ValueError("camera_id values must be unique")
        self.camera_configs = list(camera_configs)
        self.on_plate_confirmed = on_plate_confirmed
        self._pipelines: dict[str, ANPRPipeline] = {}
        self._threads: dict[str, Thread] = {}
        self.errors: dict[str, str] = {}

    def start(self) -> None:
        started = []
        try:
            for config in self.camera_configs:
                previous = self._threads.get(config.camera_id)
                if previous is not None and previous.is_alive():
                    continue
                pipeline = ANPRPipeline(
                    source=config.source, camera_id=config.camera_id,
                    camera_role=config.camera_role,
                )
                self.errors.pop(config.camera_id, None)
                thread = Thread(target=self._run_camera, args=(config, pipeline),
                                name=f"anpr-{config.camera_id}", daemon=True)
                self._pipelines[config.camera_id] = pipeline
                self._threads[config.camera_id] = thread
                started.append(config.camera_id)
                thread.start()
        except Exception as error:
            self.errors[config.camera_id] = str(error)
            logger.exception("Unable to start camera %s", config.camera_id)
            # Stop this start attempt's workers; leave existing workers alone.
            for camera_id in started:
                self._pipelines[camera_id].stop()
            for camera_id in started:
                thread = self._threads[camera_id]
                if thread.ident is not None:
                    thread.join(timeout=5)
                if not thread.is_alive():
                    self._threads.pop(camera_id)
                    self._pipelines.pop(camera_id)
            raise

    def _run_camera(self, config: CameraConfig, pipeline: ANPRPipeline) -> None:
        try:
            with closing(pipeline.run()) as events:
                for event in events:
                    self._handle_plate_event(event)
        except Exception as error:
            self.errors[config.camera_id] = str(error)
            logger.exception("Camera %s (%s) failed", config.camera_id, config.camera_name)
        finally:
            pipeline.stop()

    def _handle_plate_event(self, event: RecognitionEvent) -> None:
        if self.on_plate_confirmed is None:
            logger.info("Confirmed recognition: %s", asdict(event))
            return
        try:
            self.on_plate_confirmed(event)
        except Exception as error:
            # Consumer failure must not silently kill capture. No automatic
            # retry: delivery/idempotency policies belong to the future consumer.
            self.errors[event.camera_id] = str(error)
            logger.exception("Recognition callback failed for event %s", event.event_id)

    def stop(self, timeout: float = 5) -> None:
        if timeout < 0:
            raise ValueError("timeout must be nonnegative")
        for pipeline in self._pipelines.values():
            pipeline.stop()
        pending = []
        for camera_id, thread in list(self._threads.items()):
            if thread is current_thread():
                pending.append(camera_id)
                continue
            thread.join(timeout=timeout)
            if thread.is_alive():
                pending.append(camera_id)
            else:
                self._threads.pop(camera_id)
                self._pipelines.pop(camera_id)
        if pending:
            logger.warning("Camera workers still stopping: %s", pending)

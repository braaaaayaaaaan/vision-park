from dataclasses import dataclass
from threading import Thread, Event
from typing import Callable, Optional

from backend.anpr.pipeline import ANPRPipeline

@dataclass
class CameraConfig:
    """
    represents the camera configuration for one camera
    """

    camera_id: str 
    camera_name: str 
    camera_role: str 
    source: str | int

@dataclass
class CameraEvent:
    """
    represents the confirmed number plate detected by the camera (source)
    """

    camera_id: str 
    camera_name: str 
    camera_role: str 
    plate: str

class CameraManager:
    """
    concurrently manage multiple independent camera sources
    """

    def __init__(self, camera_configs: list[CameraConfig], on_plate_confirmed: Optional[Callable[[CameraEvent], None]] = None):
        self.camera_configs = camera_configs
        self.on_plate_confirmed = on_plate_confirmed

        self._pipelines: dict[str, ANPRPipeline] = {}
        self._threads: dict[str, Thread] = {}

        self._stop_event = Event()

    def start(self) -> None:
        """
        starts the worker for each camera for independent anpr pipeline
        """

        self._stop_event.clear()

        for config in self.camera_configs:
            if config.camera_id in self._threads: 
                continue

            pipeline = ANPRPipeline(source=config.source)

            self._pipelines[config.camera_id] = pipeline

            thread = Thread( target=self._run_camera, args=(config, pipeline), daemon=True)

            self._threads[config.camera_id] = thread

            thread.start()

    def _run_camera(self, config: CameraConfig, pipeline: ANPRPipeline) -> None:
        """
        executes the anpr pipeline for one camera
        """

        try: 
            for result in pipeline.run(): 
                if self._stop_event.is_set(): 
                    break

                event = CameraEvent( camera_id=config.camera_id, 
                                    camera_name=config.camera_name, 
                                    camera_role=config.camera_role, 
                                    plate=result.text, )

                self._handle_plate_event(event)

        except Exception as error:
            print( f"Camera '{config.camera_name}' " f"encountered an error: {error}" )

        finally:
            pipeline.stop()

    def _handle_plate_event( self, event: CameraEvent, ) -> None:
        if self.on_plate_confirmed is not None:
            self.on_plate_confirmed(event)
        else:
            print({ "camera_id": event.camera_id, 
                   "camera_name": event.camera_name, 
                   "camera_role": event.camera_role, 
                   "plate": event.plate})

    def stop(self) -> None:
        self._stop_event.set()

        for pipeline in self._pipelines.values(): 
            pipeline.stop()

        for thread in self._threads.values():
            if thread.is_alive():
                thread.join(timeout=5)

        self._pipelines.clear() 
        self._threads.clear()
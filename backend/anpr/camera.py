import cv2
from typing import Iterator

class Camera:
    """
    provides video frames from sources such as 
    video file, webcam (0), and rtsp/ip camera using opencv
    """

    def __init__(self, source):
        self.source = source
        self.capture = None

    def open(self) -> None:
        self.capture = cv2.VideoCapture(self.source)

        if not self.capture.isOpened():
            raise RuntimeError(f"Unable to open the video source: {self.source}")

    def frames(self) -> Iterator:
        if self.capture is None:
            self.open()

        while True:
            success, frame = self.capture.read()

            if not success:
                break

            #note: process the one frame at a time (do not load entire video into memory)
            yield frame

    def release(self) -> None:
        if self.capture is not None:
            self.capture.release()
            self.capture = None
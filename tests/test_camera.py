import cv2
from backend.anpr.camera import Camera

camera = Camera("data/videos/video_1.mp4")

for frame in camera.frames():
    cv2.imshow("ANPR Camera Test", frame)

    if cv2.waitKey(1) & 0xFF == ord("q"):
        break

camera.release()
cv2.destroyAllWindows
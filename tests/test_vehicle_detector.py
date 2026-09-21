from backend.anpr.camera import Camera
from backend.anpr.vehicle_tracker import VehicleTracker

camera = Camera("data/videos/video_2.mp4")
tracker = VehicleTracker()

for frame in camera.frames():
    tracked_vehicles = tracker.update(frame)

    for vehicle in tracked_vehicles:
        print(
            f"ID: {vehicle.track_id} | "
            f"Class: {vehicle.class_name} | "
            f"Confidence: {vehicle.confidence:.2f} | "
            f"BBox: {vehicle.bbox} | "
        )

camera.release()
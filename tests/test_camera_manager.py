from backend.anpr.camera_manager import CameraConfig, CameraManager

def on_plate_confirmed(event):
    print(
        f"[{event.camera_name}] "
        f"Plate: {event.plate}"
    )

def main():
    cameras = [
        CameraConfig(
            camera_id="cam_01",
            camera_name="Entrance Camera",
            camera_role="entrance",
            source="data/videos/entrance.mp4",
        ),
        CameraConfig(
            camera_id="cam_02",
            camera_name="Exit Camera",
            camera_role="exit",
            source="data/videos/exit.mp4",
        ),
    ]

    manager = CameraManager(
        camera_configs=cameras,
        on_plate_confirmed=on_plate_confirmed,
    )

    try:
        print("Starting cameras...")

        manager.start()

        input("Press ENTER to stop...\n")

    finally:
        print("Stopping cameras...")
        manager.stop()
        print("Cameras stopped.")


if __name__ == "__main__":
    main()
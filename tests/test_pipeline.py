from dataclasses import asdict
from backend.anpr.pipeline import ANPRPipeline


def main():
    pipeline = ANPRPipeline(
        source="data/videos/inti_entrance.mp4",
        camera_id="test-entrance",
        camera_role="entrance",
    )
    for event in pipeline.run():
        print(asdict(event))


if __name__ == "__main__":
    main()

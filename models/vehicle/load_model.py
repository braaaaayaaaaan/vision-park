from ultralytics import YOLO

model = YOLO("yolo26s.pt")

results = model.predict("C:/GitHub/fyp/project/data/videos/video_1.mp4")

for result in results:
    print(result)
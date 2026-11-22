
from pathlib import Path
from tkinter import Tk, filedialog
from ultralytics import YOLO

# ==========================================
# CONFIGURATION
# ==========================================

# models/vehicle/yolo26s_vehicle_finetuned.pt
# models/plate/yolo26n_np_finetuned.pt

MODEL_PATH = "models/plate/yolo26n_np_finetuned.pt"
CONFIDENCE = 0.25
IMAGE_SIZE = 640
DEVICE =  "cpu"

# ==========================================
# SELECT IMAGE
# ==========================================

root = Tk()
root.withdraw()

image_path = filedialog.askopenfilename(
    title="Select an image for YOLO detection",
    filetypes=[
        ("Image files", "*.jpg *.jpeg *.png *.bmp *.webp"),
        ("All files", "*.*")
    ]
)

root.destroy()

if not image_path:
    raise SystemExit("No image selected.")

# ==========================================
# LOAD MODEL
# ==========================================

model = YOLO(MODEL_PATH)

print("\nModel class mappings:")
for class_id, class_name in model.names.items():
    print(f"{class_id}: {class_name}")

# ==========================================
# RUN PREDICTION
# ==========================================

results = model.predict(
    source=image_path,
    conf=CONFIDENCE,
    imgsz=IMAGE_SIZE,
    device=DEVICE,
    verbose=False
)

# ==========================================
# DISPLAY DETECTIONS
# ==========================================

result = results[0]

print("\n========== DETECTION RESULTS ==========")

if result.boxes is None or len(result.boxes) == 0:
    print("No objects detected.")
else:
    for index, box in enumerate(result.boxes, start=1):
        class_id = int(box.cls.item())
        class_name = result.names[class_id]
        confidence = float(box.conf.item())
        coordinates = box.xyxy[0].tolist()

        print(f"\nDetection #{index}")
        print(f"Class ID   : {class_id}")
        print(f"Class Name : {class_name}")
        print(f"Confidence : {confidence:.2%}")
        print(f"Bounding Box: {[round(x, 1) for x in coordinates]}")

print(f"\nTotal detections: {len(result.boxes) if result.boxes is not None else 0}")

# ==========================================
# SAVE AND DISPLAY IMAGE
# ==========================================

output_dir = Path("models/detection_results/np_detection_results")
output_dir.mkdir(exist_ok=True)

output_path = output_dir / f"{Path(image_path).stem}_detected.jpg"

result.save(filename=str(output_path))
print(f"\nAnnotated image saved to: {output_path.resolve()}")

result.show()

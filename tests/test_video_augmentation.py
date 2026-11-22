
import cv2
import albumentations as A
import subprocess
import shutil
from pathlib import Path

# ==========================================
# CONFIGURATION
# ==========================================

# Resolve paths relative to VisionPark root
PROJECT_ROOT = Path(__file__).resolve().parent.parent

INPUT_VIDEO = PROJECT_ROOT / "data/videos/inti_entrance.mp4"

OUTPUT_DIR = PROJECT_ROOT / "tests/augmentation"
OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

TEMP_VIDEO = OUTPUT_DIR / "inti_entrance_rain.mp4"
FINAL_VIDEO = OUTPUT_DIR / "inti_entrance_rain_h264.mp4"

# ==========================================
# FIND FFMPEG
# ==========================================

def find_ffmpeg():
    # First try system-installed FFmpeg
    ffmpeg_path = shutil.which("ffmpeg")

    if ffmpeg_path:
        return ffmpeg_path

    # Otherwise try imageio-ffmpeg
    try:
        import imageio_ffmpeg
        return imageio_ffmpeg.get_ffmpeg_exe()
    except (ImportError, RuntimeError, OSError):
        raise RuntimeError(
            "FFmpeg was not found.\n"
            "Install it using:\n"
            "python -m pip install imageio-ffmpeg"
        )

# ==========================================
# VIDEO VALIDATION
# ==========================================

if not INPUT_VIDEO.is_file():
    raise FileNotFoundError(
        f"Input video not found:\n{INPUT_VIDEO}"
    )

print(f"Input video: {INPUT_VIDEO}")

cap = cv2.VideoCapture(str(INPUT_VIDEO))

if not cap.isOpened():
    raise RuntimeError("Could not open input video.")

fps = cap.get(cv2.CAP_PROP_FPS)
width = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
height = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))

if fps <= 0 or width <= 0 or height <= 0:
    cap.release()
    raise RuntimeError("Invalid video properties.")

print(f"Resolution: {width}x{height}")
print(f"FPS: {fps:.2f}")

# ==========================================
# HEAVY RAIN + VERY LIGHT FOG
# (CLEAR NUMBER PLATE, NO DARKNESS)
# ==========================================

transform = A.Compose([
    # 1. Heavy rain
    A.RandomRain(
        slant_range=(-8, 8),
        drop_length=16,
        drop_width=1,
        drop_color=(190, 190, 190),
        blur_value=1,
        brightness_coefficient=0.98,
        rain_type="heavy",
        p=1.0
    ),

    # 2. Very light fog
    A.RandomFog(
        fog_coef_range=(0.05, 0.10),
        alpha_coef=0.02,
        p=1.0
    )
])

# ==========================================
# CREATE VIDEO WRITER
# ==========================================

out = cv2.VideoWriter(
    str(TEMP_VIDEO),
    cv2.VideoWriter_fourcc(*"mp4v"),
    fps,
    (width, height)
)

if not out.isOpened():
    cap.release()
    raise RuntimeError("Could not create output video.")

# ==========================================
# PROCESS VIDEO
# ==========================================

print("\nApplying rain augmentation...")

frame_count = 0

try:
    while True:
        ret, frame = cap.read()

        if not ret:
            break

        # Convert BGR to RGB
        rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)

        # Apply rain augmentation
        augmented = transform(image=rgb)["image"]

        # Convert RGB back to BGR
        result = cv2.cvtColor(
            augmented,
            cv2.COLOR_RGB2BGR
        )

        out.write(result)
        frame_count += 1

finally:
    cap.release()
    out.release()

if frame_count == 0:
    raise RuntimeError("No frames were processed.")

print(f"Processed frames: {frame_count}")
print(f"Temporary video saved: {TEMP_VIDEO}")

# ==========================================
# CONVERT VIDEO TO H.264
# ==========================================

print("\nConverting video to H.264...")

ffmpeg_path = find_ffmpeg()

command = [
    ffmpeg_path,
    "-y",
    "-i", str(TEMP_VIDEO),
    "-c:v", "libx264",
    "-pix_fmt", "yuv420p",
    "-crf", "20",
    "-preset", "medium",
    "-movflags", "+faststart",
    "-an",
    str(FINAL_VIDEO)
]

try:
    subprocess.run(
        command,
        check=True
    )

except subprocess.CalledProcessError as error:
    raise RuntimeError(
        f"FFmpeg conversion failed: {error}"
    ) from error

# ==========================================
# VERIFY OUTPUT
# ==========================================

if not FINAL_VIDEO.is_file():
    raise RuntimeError(
        "H.264 output video was not created."
    )

if FINAL_VIDEO.stat().st_size == 0:
    raise RuntimeError(
        "H.264 output video is empty."
    )

print("\n========== COMPLETED ==========")
print(f"Input video: {INPUT_VIDEO.name}")
print(f"Frames processed: {frame_count}")
print(f"Resolution: {width}x{height}")
print(f"FPS: {fps:.2f}")
print(f"Output: {FINAL_VIDEO}")
print(f"File size: {FINAL_VIDEO.stat().st_size / (1024 * 1024):.2f} MB")
print("================================")

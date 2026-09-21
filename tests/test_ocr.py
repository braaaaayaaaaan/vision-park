import time
import cv2

from backend.anpr.ocr import OCR


IMAGE_PATH = "data/images/image_3.jpeg"

def main():
    # Load cropped license plate image
    plate_image = cv2.imread(IMAGE_PATH)

    if plate_image is None:
        raise FileNotFoundError(
            f"Unable to load plate image: {IMAGE_PATH}"
        )

    # Initialize OCR model
    ocr = OCR()

    # Measure OCR inference time
    start_time = time.perf_counter()

    result = ocr.recognise(plate_image)

    end_time = time.perf_counter()

    inference_time_ms = (end_time - start_time) * 1000

    # Display result
    if result is None:
        print("No text recognised.")
    else:
        print(f"Text:       {result.text}")
        print(f"Confidence: {result.confidence:.4f}")

    print(f"Time:       {inference_time_ms:.2f} ms")


if __name__ == "__main__":
    main()
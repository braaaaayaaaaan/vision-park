from paddleocr import TextRecognition
from dataclasses import dataclass
from typing import Optional

@dataclass
class OCRResult:
    """
    represents the results of extracted text from number plates
    """

    text: str
    confidence: float

class OCR:
    """
    performs text recognition on number plates
    """

    def __init__(self, model_name: str = "PP-OCRv5_mobile_rec", device: str = "gpu", engine: str = "paddle_static"):
        self.model_name = model_name
        self.device = device
        self.engine = engine

        self.model = TextRecognition(
            model_name=self.model_name,
            device=self.device,
            engine=self.engine
        )

    def recognise(self, plate_image) -> Optional[OCRResult]:
        results = self.model.predict(
            input=plate_image,
            batch_size=1
        )

        if not results:
            return None

        result = results[0]

        text = result["rec_text"]
        confidence = float(result["rec_score"])

        if not text:
            return None

        return OCRResult(
            text=text,
            confidence=confidence
        )
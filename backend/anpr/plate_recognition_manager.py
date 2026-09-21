from collections import Counter
from dataclasses import dataclass, field
from typing import Dict, Optional

from backend.anpr.plate_processor import ProcessedPlate

@dataclass
class PlateObservation:
    """
    represents text recognition (ocr) observation for one vehicle
    """

    text: str
    ocr_confidence: float
    plate_confidence: float

@dataclass
class VehicleRecognitionState:
    """
    records the series of number plate readings for one vehicle
    """

    track_id: int
    observations: list[PlateObservation] = field(default_factory=list)
    confirmed_plate: Optional[str] = None

class PlateRecognitionManager:
    """
    aggregate the readings for the same vehicle
    """

    def __init__(self, minimum_observations: int = 5, confirmation_ratio: float = 0.6, 
                 minimum_ocr_confidence: float = 0.85, maximum_observations: int = 10,):

        self.minimum_observations = minimum_observations
        self.confirmation_ratio = confirmation_ratio
        self.minimum_ocr_confidence = minimum_ocr_confidence
        self.maximum_observations = maximum_observations

        self._vehicles: Dict[int, VehicleRecognitionState] = {}

    def observe(self, result: ProcessedPlate) -> Optional[str]:
        track_id = result.track_id

        state = self._vehicles.setdefault(
            track_id,
            VehicleRecognitionState(track_id=track_id)
        )

        if state.confirmed_plate is not None:
            return state.confirmed_plate

        text = self._normalise_text(result.text)

        if not text:
            return None

        observation = PlateObservation(
            text=text,
            ocr_confidence=result.ocr_confidence,
            plate_confidence=result.plate_confidence,
        )

        state.observations.append(observation)

        if len(state.observations) > self.maximum_observations:
            state.observations.pop(0)

        self._try_confirm(state)

        return state.confirmed_plate

    def is_confirmed(self, track_id: int) -> bool:
        state = self._vehicles.get(track_id)

        return (
            state is not None
            and state.confirmed_plate is not None
        )

    def get_confirmed_plate(self, track_id: int) -> Optional[str]:
        state = self._vehicles.get(track_id)

        if state is None:
            return None

        return state.confirmed_plate

    def remove_vehicle(self, track_id: int) -> None:
        self._vehicles.pop(track_id, None)

    def _try_confirm(self, state: VehicleRecognitionState) -> None:
        if len(state.observations) < self.minimum_observations:
            return

        valid_observations = [
            observation
            for observation in state.observations
            if observation.ocr_confidence >= self.minimum_ocr_confidence
        ]

        if len(valid_observations) < self.minimum_observations:
            return

        counts = Counter(
            observation.text
            for observation in valid_observations
        )

        candidate, candidate_count = counts.most_common(1)[0]

        ratio = candidate_count / len(valid_observations)

        if ratio >= self.confirmation_ratio:
            state.confirmed_plate = candidate

    @staticmethod
    def _normalise_text(text: str) -> str:
        return "".join(
            character
            for character in text.upper()
            if character.isalnum()
        )
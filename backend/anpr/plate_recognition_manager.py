from __future__ import annotations

from collections import Counter
from dataclasses import dataclass, field
from math import isfinite
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from backend.anpr.plate_processor import ProcessedPlate


@dataclass(frozen=True)
class PlateObservation:
    raw_text: str
    text: str
    ocr_confidence: float
    plate_confidence: float


@dataclass(frozen=True)
class FrameObservation:
    frame_index: int
    observations: tuple[PlateObservation, ...]
    # None means this frame has no unambiguous, qualifying vote.
    vote: str | None


@dataclass
class VehicleRecognitionState:
    track_id: int
    observations: list[FrameObservation] = field(default_factory=list)
    confirmed_plate: str | None = None
    last_frame_index: int = -1


class PlateRecognitionManager:
    """One vote per track per frame; return a plate only on new confirmation."""

    def __init__(self, minimum_observations: int = 5, confirmation_ratio: float = 0.6,
                 minimum_ocr_confidence: float = 0.85, maximum_observations: int = 10):
        if type(minimum_observations) is not int or type(maximum_observations) is not int:
            raise ValueError("Observation counts must be integers")
        if not 1 <= minimum_observations <= maximum_observations:
            raise ValueError("Require 1 <= minimum_observations <= maximum_observations")
        if not 0 < confirmation_ratio <= 1:
            raise ValueError("confirmation_ratio must be in (0, 1]")
        if not 0 <= minimum_ocr_confidence <= 1:
            raise ValueError("minimum_ocr_confidence must be in [0, 1]")
        self.minimum_observations = minimum_observations
        self.confirmation_ratio = confirmation_ratio
        self.minimum_ocr_confidence = minimum_ocr_confidence
        self.maximum_observations = maximum_observations
        self._vehicles: dict[int, VehicleRecognitionState] = {}

    def observe_frame(self, track_id: int, frame_index: int,
                      results: list[ProcessedPlate]) -> str | None:
        """Pass ALL readings for this track/frame together, including an empty list.

        Different qualifying texts in one frame abstain rather than letting the
        highest-confidence reading decide. Duplicate identical texts count once.
        Raw readings remain in the bounded diagnostic window.
        """
        if any(result.track_id != track_id for result in results):
            raise ValueError("Observation track_id does not match the tracked vehicle")
        state = self._vehicles.setdefault(track_id, VehicleRecognitionState(track_id))
        if state.confirmed_plate is not None or frame_index <= state.last_frame_index:
            return None
        state.last_frame_index = frame_index
        observations = tuple(
            PlateObservation(result.text, self._normalise_text(result.text),
                             result.ocr_confidence, result.plate_confidence)
            for result in results
        )
        candidates = {
            observation.text for observation in observations
            if observation.text and isfinite(observation.ocr_confidence)
            and self.minimum_ocr_confidence <= observation.ocr_confidence <= 1
        }
        vote = next(iter(candidates)) if len(candidates) == 1 else None
        state.observations.append(FrameObservation(frame_index, observations, vote))
        del state.observations[:-self.maximum_observations]
        votes = [frame.vote for frame in state.observations if frame.vote is not None]
        if len(votes) < self.minimum_observations:
            return None
        counts = Counter(votes)
        candidate, count = counts.most_common(1)[0]
        # An explicit tie check also protects configurable ratios <= 0.5.
        if sum(value == count for value in counts.values()) != 1:
            return None
        if count / len(votes) >= self.confirmation_ratio:
            state.confirmed_plate = candidate
            return candidate
        return None

    def is_confirmed(self, track_id: int) -> bool:
        return self.get_confirmed_plate(track_id) is not None

    def get_confirmed_plate(self, track_id: int) -> str | None:
        state = self._vehicles.get(track_id)
        return state.confirmed_plate if state is not None else None

    def remove_vehicle(self, track_id: int) -> None:
        self._vehicles.pop(track_id, None)

    def retain_tracks(self, track_ids: set[int]) -> None:
        """Keep active AND temporarily lost ByteTrack IDs until tracker retirement."""
        for track_id in self._vehicles.keys() - track_ids:
            self.remove_vehicle(track_id)

    def clear(self) -> None:
        self._vehicles.clear()

    @staticmethod
    def _normalise_text(text: str) -> str:
        return "".join(character for character in text.upper() if character.isalnum())

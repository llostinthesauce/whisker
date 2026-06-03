from typing import List, Optional

from pydantic import BaseModel


class ModelProfileResponse(BaseModel):
    id: str
    label: str
    engine: str
    model: str
    speed: str
    description: str


class HealthResponse(BaseModel):
    ok: bool
    server: str
    version: str
    engine: str
    model: str
    default_model_id: str
    models: List[ModelProfileResponse]
    cleanup: List[str]
    max_duration_seconds: float


class TranscriptSegment(BaseModel):
    start: Optional[float] = None
    end: Optional[float] = None
    text: Optional[str] = None


class TranscriptionResponse(BaseModel):
    id: str
    text: str
    cleaned_text: Optional[str]
    duration_seconds: float
    engine: str
    model: str
    model_id: str
    processing_seconds: Optional[float]
    segments: List[TranscriptSegment]
    warnings: List[str]

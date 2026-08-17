import uuid
from datetime import date, datetime

from pydantic import BaseModel


class ExamInfoOut(BaseModel):
    id: str
    name: str
    full_name: str
    region: str
    description: str
    default_prep_weeks: int


class SetupCreate(BaseModel):
    exam_id: str
    custom_exam_name: str = ""
    target_exam_date: date
    start_date: date
    prep_level: str
    daily_study_minutes: int = 60
    available_days_per_week: list[int] = [1, 2, 3, 4, 5]
    study_preference: str = "one_specialty_per_day"
    goal: str = "pass_comfortably"
    study_mode: str = "standard"


class SetupOut(BaseModel):
    id: uuid.UUID
    exam_id: str
    custom_exam_name: str
    target_exam_date: date
    start_date: date
    prep_level: str
    daily_study_minutes: int
    available_days_per_week: list[int]
    study_preference: str
    goal: str
    study_mode: str
    created_at: datetime

    model_config = {"from_attributes": True}


class TopicOut(BaseModel):
    id: uuid.UUID
    key: str
    title: str
    estimated_minutes: int
    difficulty: str
    high_yield: bool
    learning_objectives: list[str]
    suggested_resources: list[str]
    notes: str = ""
    checklists: list = []
    is_bookmarked: bool = False
    status: str = "pending"
    confidence_rating: int = 3

    model_config = {"from_attributes": True}


class TopicNotesUpdate(BaseModel):
    notes: str


class TopicMetaUpdate(BaseModel):
    """Partial update of a topic's personal meta: notes, checklist items
    (list of {"id", "text", "done"}), and bookmark flag."""

    notes: str | None = None
    checklists: list | None = None
    is_bookmarked: bool | None = None
    difficulty: str | None = None


class SpecialtyCreate(BaseModel):
    title: str
    description: str = ""


class TopicCreate(BaseModel):
    title: str
    estimated_minutes: int = 45
    difficulty: str = "moderate"


class RegenerateResult(BaseModel):
    created_sessions: int


class SpecialtyOut(BaseModel):
    id: uuid.UUID
    key: str
    title: str
    description: str
    icon: str
    topics: list[TopicOut]

    model_config = {"from_attributes": True}


class SessionOut(BaseModel):
    id: uuid.UUID
    topic_id: uuid.UUID
    topic_title: str
    specialty_title: str
    date: date
    type: str
    revision_iteration: int | None
    estimated_minutes: int
    status: str
    completed_at: datetime | None
    actual_minutes_spent: int | None
    confidence_rating: int | None
    is_moved: bool
    notes: str


class SessionUpdate(BaseModel):
    status: str | None = None
    actual_minutes_spent: int | None = None
    confidence_rating: int | None = None
    notes: str | None = None


class StreakOut(BaseModel):
    current_streak: int
    longest_streak: int
    last_studied_date: date | None
    total_study_days: int

    model_config = {"from_attributes": True}


class CatchupResult(BaseModel):
    redistributed_count: int


class PlannerStats(BaseModel):
    total_topics: int
    completed_topics_count: int
    remaining_topics_count: int
    syllabus_progress_pct: int
    schedule_progress_pct: int
    total_sessions: int
    completed_sessions: int
    total_revision_sessions: int
    completed_revisions: int
    total_study_hours: float
    specialty_topic_counts: dict
    readiness_score: int
    avg_confidence: float

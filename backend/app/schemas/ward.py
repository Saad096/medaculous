import uuid
from datetime import datetime

from pydantic import BaseModel


class ShiftCreate(BaseModel):
    hospital: str = ""
    ward: str
    specialty: str
    shift_type: str


class ShiftOut(BaseModel):
    id: uuid.UUID
    hospital: str
    ward: str
    specialty: str
    shift_type: str
    active: bool
    started_at: datetime

    model_config = {"from_attributes": True}


class PatientCreate(BaseModel):
    initials: str
    age: str = ""
    dob: str = ""
    sex: str
    room_number: str = ""
    bed_number: str = ""
    diagnosis: str = ""
    co_morbids: str = ""
    dnar: bool = False
    notes: str = ""


class PatientUpdate(BaseModel):
    initials: str | None = None
    age: str | None = None
    dob: str | None = None
    sex: str | None = None
    room_number: str | None = None
    bed_number: str | None = None
    diagnosis: str | None = None
    co_morbids: str | None = None
    dnar: bool | None = None
    reviewed: bool | None = None
    sort_order: int | None = None
    notes: str | None = None


class PatientOut(BaseModel):
    id: uuid.UUID
    initials: str
    age: str
    dob: str
    sex: str
    room_number: str
    bed_number: str
    diagnosis: str
    co_morbids: str
    dnar: bool
    reviewed: bool
    sort_order: int
    notes: str

    model_config = {"from_attributes": True}


class TaskCreate(BaseModel):
    patient_id: uuid.UUID
    title: str
    priority: str = "Medium"
    note: str = ""


class TaskUpdate(BaseModel):
    title: str | None = None
    completed: bool | None = None
    priority: str | None = None
    note: str | None = None


class TaskOut(BaseModel):
    id: uuid.UUID
    patient_id: uuid.UUID
    title: str
    completed: bool
    priority: str
    note: str

    model_config = {"from_attributes": True}

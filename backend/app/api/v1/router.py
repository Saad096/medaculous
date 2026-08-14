from fastapi import APIRouter

from app.api.v1.admin import router as admin_router
from app.api.v1.ai import router as ai_router
from app.api.v1.auth import router as auth_router
from app.api.v1.diseases import router as diseases_router
from app.api.v1.exam_planner import router as exam_planner_router
from app.api.v1.formulary import router as formulary_router
from app.api.v1.knowledge_hub import router as knowledge_hub_router
from app.api.v1.notes import router as notes_router
from app.api.v1.osce import router as osce_router
from app.api.v1.pharmacy import router as pharmacy_router
from app.api.v1.symptoms import router as symptoms_router
from app.api.v1.ward import router as ward_router

api_router = APIRouter(prefix="/api/v1")
api_router.include_router(auth_router)
api_router.include_router(ai_router)
api_router.include_router(notes_router)
api_router.include_router(diseases_router)
api_router.include_router(symptoms_router)
api_router.include_router(pharmacy_router)
api_router.include_router(formulary_router)
api_router.include_router(knowledge_hub_router)
api_router.include_router(ward_router)
api_router.include_router(exam_planner_router)
api_router.include_router(osce_router)
api_router.include_router(admin_router)

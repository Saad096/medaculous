"""Cross-user ownership/authorization tests for the FastAPI backend.

Each test creates a resource as user_a, then asserts user_b cannot read,
modify, or delete it (404, not 403 — matching the ownership-check pattern
already used throughout app/api/v1/*.py, which returns 404 rather than 403
to avoid leaking whether a resource exists at all).
"""
import pytest

# Must match asyncio_default_fixture_loop_scope=session (pytest.ini) — the shared
# db_session/client fixtures set up connections on the session-scoped loop, so
# every test in this module needs to run on that same loop or asyncpg connections
# end up bound to a closed/mismatched loop ("attached to a different loop").
pytestmark = pytest.mark.asyncio(loop_scope="session")


async def test_notes_are_owned(client, user_a, user_b, auth_headers):
    create = await client.post("/notes", json={"title": "Private note"}, headers=auth_headers(user_a))
    assert create.status_code == 201
    note_id = create.json()["id"]

    as_owner = await client.get(f"/notes/{note_id}", headers=auth_headers(user_a))
    assert as_owner.status_code == 200

    as_other = await client.get(f"/notes/{note_id}", headers=auth_headers(user_b))
    assert as_other.status_code == 404

    patch_other = await client.patch(f"/notes/{note_id}", json={"title": "hacked"}, headers=auth_headers(user_b))
    assert patch_other.status_code == 404

    delete_other = await client.delete(f"/notes/{note_id}", headers=auth_headers(user_b))
    assert delete_other.status_code == 404


async def test_note_list_is_scoped_per_user(client, user_a, user_b, auth_headers):
    await client.post("/notes", json={"title": "A's note"}, headers=auth_headers(user_a))
    await client.post("/notes", json={"title": "B's note"}, headers=auth_headers(user_b))

    a_notes = (await client.get("/notes", headers=auth_headers(user_a))).json()
    b_notes = (await client.get("/notes", headers=auth_headers(user_b))).json()

    assert {n["title"] for n in a_notes} == {"A's note"}
    assert {n["title"] for n in b_notes} == {"B's note"}


async def test_knowledge_hub_pdf_metadata_is_owned(client, user_a, user_b, auth_headers):
    folder = await client.post("/knowledge-hub/folders", json={"name": "Cardiology"}, headers=auth_headers(user_a))
    assert folder.status_code == 201
    folder_id = folder.json()["id"]

    a_folders = (await client.get("/knowledge-hub/folders", headers=auth_headers(user_a))).json()
    b_folders = (await client.get("/knowledge-hub/folders", headers=auth_headers(user_b))).json()
    assert any(f["id"] == folder_id for f in a_folders)
    assert not any(f["id"] == folder_id for f in b_folders)

    as_other_delete = await client.delete(f"/knowledge-hub/folders/{folder_id}", headers=auth_headers(user_b))
    assert as_other_delete.status_code == 404


async def test_ward_patients_are_owned(client, user_a, user_b, auth_headers):
    shift = await client.post(
        "/ward/shift",
        json={"ward": "Medical", "specialty": "General Medicine", "shift_type": "Day"},
        headers=auth_headers(user_a),
    )
    assert shift.status_code == 201

    patient = await client.post(
        "/ward/patients",
        json={"initials": "J.D.", "sex": "M", "notes": "confidential"},
        headers=auth_headers(user_a),
    )
    assert patient.status_code == 201
    patient_id = patient.json()["id"]

    b_patients = (await client.get("/ward/patients", headers=auth_headers(user_b))).json()
    assert not any(p["id"] == patient_id for p in b_patients)

    patch_other = await client.patch(
        f"/ward/patients/{patient_id}", json={"notes": "leaked"}, headers=auth_headers(user_b)
    )
    assert patch_other.status_code == 404

    delete_other = await client.delete(f"/ward/patients/{patient_id}", headers=auth_headers(user_b))
    assert delete_other.status_code == 404


async def test_osce_favorites_and_progress_are_owned(client, user_a, user_b, auth_headers):
    stations = (await client.get("/osce/stations", headers=auth_headers(user_a))).json()
    assert stations, "expected seeded OSCE stations"
    station_id = stations[0]["id"]
    step_id = stations[0]["sections"][0]["steps"][0]["id"]

    fav = await client.post(f"/osce/favorites/{station_id}", headers=auth_headers(user_a))
    assert fav.status_code == 201

    progress = await client.patch(
        f"/osce/steps/{step_id}/progress", json={"checked": True}, headers=auth_headers(user_a)
    )
    assert progress.status_code == 204

    b_stations = (await client.get("/osce/stations", headers=auth_headers(user_b))).json()
    b_station = next(s for s in b_stations if s["id"] == station_id)
    assert b_station["is_favorite"] is False
    b_step = next(
        step
        for section in b_station["sections"]
        for step in section["steps"]
        if step["id"] == step_id
    )
    assert b_step["checked"] is False


async def test_exam_planner_setup_is_owned(client, user_a, user_b, auth_headers):
    exams = await client.get("/exam-planner/exams", headers=auth_headers(user_a))
    assert exams.status_code == 200

    unauthenticated = await client.get("/exam-planner/exams")
    assert unauthenticated.status_code == 401

    setup = await client.post(
        "/exam-planner/setup",
        json={
            "exam_id": "plab1",
            "target_exam_date": "2027-01-01",
            "start_date": "2026-08-01",
            "prep_level": "intermediate",
            "daily_study_minutes": 60,
            "available_days_per_week": [1, 2, 3, 4, 5],
            "study_preference": "one_specialty_per_day",
            "goal": "pass_comfortably",
            "study_mode": "standard",
        },
        headers=auth_headers(user_a),
    )
    assert setup.status_code == 201

    b_setup = await client.get("/exam-planner/setup", headers=auth_headers(user_b))
    assert b_setup.status_code == 200
    assert b_setup.json() is None


_TEST_MEDICATION = {
    "generic_name": "Paracetamol",
    "drug_class": "Analgesic",
    "brand_names": ["Panadol"],
    "adult_dose": "500-1000mg",
    "pediatric_dose": "15mg/kg",
    "route": "Oral",
    "frequency": "Every 4-6 hours",
    "max_daily_dose": "4000mg",
    "typical_duration": "3-5 days",
    "mechanism_of_action": "COX inhibition",
    "side_effects": ["Nausea"],
    "contraindications": ["Severe hepatic impairment"],
    "interactions": ["Warfarin"],
    "pregnancy_safety": "Safe",
    "breastfeeding_safety": "Safe",
    "renal_adjustment": "None",
    "hepatic_adjustment": "Avoid in severe impairment",
    "monitoring_requirements": "LFTs if prolonged use",
    "tier": "First-line treatment",
    "ranking_rationale": "Standard first-line analgesic",
    "clinical_references": [],
}


async def test_pharmacy_favorites_are_owned(client, user_a, user_b, auth_headers):
    create = await client.post(
        "/pharmacy/favorites",
        json={"medication": _TEST_MEDICATION},
        headers=auth_headers(user_a),
    )
    assert create.status_code == 201
    favorite_id = create.json()["id"]

    b_list = (await client.get("/pharmacy/favorites", headers=auth_headers(user_b))).json()
    assert b_list == []

    delete_other = await client.delete(f"/pharmacy/favorites/{favorite_id}", headers=auth_headers(user_b))
    assert delete_other.status_code == 404


async def test_unauthenticated_requests_are_rejected(client):
    for method, path in [
        ("GET", "/notes"),
        ("GET", "/ward/patients"),
        ("GET", "/knowledge-hub/folders"),
        ("GET", "/osce/stations"),
        ("GET", "/exam-planner/stats"),
        ("GET", "/pharmacy/favorites"),
    ]:
        response = await client.request(method, path)
        assert response.status_code == 401, f"{method} {path} should require auth"

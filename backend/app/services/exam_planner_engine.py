"""Port of the legacy src/services/examPlannerEngine.ts — schedule
generation, adaptive catch-up, spaced-repetition revision scheduling,
streak update, and readiness-score calculation. Kept as pure functions
operating on plain dicts/dataclasses so the algorithm logic mirrors the
original file line-for-line and is easy to diff against it.
"""
from datetime import date, timedelta


def get_date_range(start: date, end: date) -> list[date]:
    days = (end - start).days
    return [start + timedelta(days=i) for i in range(days + 1)] if days >= 0 else []


def _available_dates(dates: list[date], study_mode: str, available_days_per_week: list[int]) -> list[date]:
    def is_available(d: date) -> bool:
        # Python's Monday=0..Sunday=6; legacy JS Date.getDay() is Sunday=0..Saturday=6.
        dow = (d.weekday() + 1) % 7
        if study_mode == "weekend":
            return dow in (0, 6)
        return dow in available_days_per_week

    filtered = [d for d in dates if is_available(d)]
    return filtered if filtered else dates


def generate_study_schedule(setup: dict, specialties: list[dict]) -> list[dict]:
    """specialties: [{"id", "key", "topics": [{"id", "key", "title", "estimated_minutes", "high_yield", ...}]}]"""
    all_topics = []
    for sp in specialties:
        for tp in sp["topics"]:
            all_topics.append({**tp, "specialty_id": sp["id"]})

    if not all_topics:
        return []

    ordered = list(all_topics)
    if setup["study_preference"] == "mixed_specialties":
        by_specialty = {sp["id"]: list(sp["topics"]) for sp in specialties}
        ordered = []
        added = True
        while added:
            added = False
            for sp in specialties:
                bucket = by_specialty.get(sp["id"])
                if bucket:
                    topic = bucket.pop(0)
                    ordered.append({**topic, "specialty_id": sp["id"]})
                    added = True
    elif setup["study_preference"] == "randomized":
        ordered.sort(key=lambda t: t["title"])

    if setup["study_mode"] == "last_minute":
        ordered.sort(key=lambda t: 0 if t.get("high_yield") else 1)

    date_keys = get_date_range(setup["start_date"], setup["target_exam_date"])
    available_dates = _available_dates(date_keys, setup["study_mode"], setup["available_days_per_week"])
    if not available_dates:
        available_dates = date_keys

    target_daily_minutes = (
        round(setup["daily_study_minutes"] * 1.3) if setup["study_mode"] == "intensive" else setup["daily_study_minutes"]
    )

    sessions = []
    topic_idx = 0
    for current_date in available_dates:
        if topic_idx >= len(ordered):
            break
        daily_minutes = 0
        while topic_idx < len(ordered) and (daily_minutes < target_daily_minutes or daily_minutes == 0):
            topic = ordered[topic_idx]
            est = topic.get("estimated_minutes") or 45
            sessions.append({
                "date": current_date,
                "topic_id": topic["id"],
                "type": "study",
                "estimated_minutes": est,
                "status": "pending",
            })
            daily_minutes += est
            topic_idx += 1
            if daily_minutes >= target_daily_minutes + 15:
                break

    if topic_idx < len(ordered) and available_dates:
        day_cursor = 0
        while topic_idx < len(ordered):
            current_date = available_dates[day_cursor % len(available_dates)]
            topic = ordered[topic_idx]
            sessions.append({
                "date": current_date,
                "topic_id": topic["id"],
                "type": "study",
                "estimated_minutes": topic.get("estimated_minutes") or 45,
                "status": "pending",
            })
            topic_idx += 1
            day_cursor += 1

    return sessions


def compute_adaptive_catchup(missed_sessions: list[dict], setup: dict, today: date) -> dict[str, date]:
    """Redistributes past-due pending sessions across future available study
    dates. Returns {session_id: new_date} for the caller to apply — pure
    function, no DB access, mirrors runAdaptiveCatchup's redistribution loop."""
    future_dates = _available_dates(
        get_date_range(today, setup["target_exam_date"]), setup["study_mode"], setup["available_days_per_week"]
    )
    if not future_dates:
        return {}
    reassignments = {}
    for i, session in enumerate(missed_sessions):
        reassignments[session["id"]] = future_dates[i % len(future_dates)]
    return reassignments


def get_revision_intervals(difficulty: str) -> list[int]:
    if difficulty == "difficult":
        return [1, 2, 5, 9, 16, 30]
    if difficulty in ("easy", "mastered"):
        return [3, 10, 30]
    return [1, 3, 7, 14, 30]


def schedule_topic_revisions(
    topic_id, completion_date: date, difficulty: str, target_exam_date: date, existing_sessions: list[dict]
) -> list[dict]:
    """Returns NEW revision session dicts to insert (does not mutate existing_sessions)."""
    new_sessions = []
    for iteration, days_to_add in enumerate(get_revision_intervals(difficulty), start=1):
        rev_date = completion_date + timedelta(days=days_to_add)
        if rev_date > target_exam_date:
            continue
        exists = any(
            s["topic_id"] == topic_id and s["type"] == "revision" and s["date"] == rev_date for s in existing_sessions
        )
        if not exists:
            new_sessions.append({
                "topic_id": topic_id,
                "date": rev_date,
                "type": "revision",
                "revision_iteration": iteration,
                "estimated_minutes": 20,
                "status": "pending",
            })
    return new_sessions


def update_streak_on_completion(streak: dict, today: date) -> dict:
    if streak.get("last_studied_date") == today:
        return streak
    yesterday = today - timedelta(days=1)
    new_current = 1
    if streak.get("last_studied_date") == yesterday:
        new_current = streak["current_streak"] + 1
    return {
        "current_streak": new_current,
        "longest_streak": max(streak["longest_streak"], new_current),
        "last_studied_date": today,
        "total_study_days": streak["total_study_days"] + 1,
    }


def calculate_planner_stats(
    specialties: list[dict], topic_meta_by_id: dict, sessions: list[dict], streak: dict | None
) -> dict:
    total_topics = sum(len(sp["topics"]) for sp in specialties)
    specialty_topic_counts = {}
    for sp in specialties:
        specialty_topic_counts[sp["key"]] = {"total": len(sp["topics"]), "completed": 0, "name": sp["title"]}

    completed_topics_count = 0
    total_study_minutes_logged = 0
    topic_to_specialty_key = {t["id"]: sp["key"] for sp in specialties for t in sp["topics"]}

    for topic_id, meta in topic_meta_by_id.items():
        if meta["status"] == "completed":
            completed_topics_count += 1
            spec_key = topic_to_specialty_key.get(topic_id)
            if spec_key and spec_key in specialty_topic_counts:
                specialty_topic_counts[spec_key]["completed"] += 1
        total_study_minutes_logged += meta.get("study_time_minutes") or 0

    total_sessions = len(sessions)
    completed_sessions = sum(1 for s in sessions if s["status"] == "completed")
    revision_sessions = [s for s in sessions if s["type"] == "revision"]
    completed_revisions = sum(1 for s in revision_sessions if s["status"] == "completed")

    syllabus_progress_pct = round((completed_topics_count / total_topics) * 100) if total_topics else 0
    schedule_progress_pct = round((completed_sessions / total_sessions) * 100) if total_sessions else 0

    confidences = [m.get("confidence_rating") or 3 for m in topic_meta_by_id.values()]
    avg_confidence = (sum(confidences) / len(confidences)) if confidences else 3

    streak_factor = min(100, (streak["current_streak"] if streak else 0) * 10)
    readiness_score = min(
        100,
        round(
            syllabus_progress_pct * 0.5
            + (completed_revisions / max(1, len(revision_sessions))) * 25
            + (avg_confidence / 5) * 15
            + (streak_factor / 100) * 10
        ),
    )

    return {
        "total_topics": total_topics,
        "completed_topics_count": completed_topics_count,
        "remaining_topics_count": max(0, total_topics - completed_topics_count),
        "syllabus_progress_pct": syllabus_progress_pct,
        "schedule_progress_pct": schedule_progress_pct,
        "total_sessions": total_sessions,
        "completed_sessions": completed_sessions,
        "total_revision_sessions": len(revision_sessions),
        "completed_revisions": completed_revisions,
        "total_study_hours": round(total_study_minutes_logged / 60, 1),
        "specialty_topic_counts": specialty_topic_counts,
        "readiness_score": readiness_score,
        "avg_confidence": round(avg_confidence, 1),
    }

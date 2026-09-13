#!/usr/bin/env python3
"""Generate JSONL study-session data matching the app import schema.

Each line is one session:
  term, course, start_time, end_time, study_time_seconds,
  activities[{name, start_time, duration_seconds}], note?, focus_rating?

Term first/last days are inferred from session dates on import, so the
generated range includes today so the term becomes active.

Usage:
  python3 scripts/generate-fake-data.py
  python3 scripts/generate-fake-data.py --days 16 --out samples/fake-study-data.json
"""

from __future__ import annotations

import argparse
import json
import random
from datetime import datetime, timedelta, timezone
from pathlib import Path

TERM = "Fall 2026"
COURSES = [
    "Linear Algebra",
    "Organic Chemistry",
    "Algorithms",
    "Macroeconomics",
    "Spanish",
]
ACTIVITIES = [
    "Reading",
    "Practice Problems",
    "Lecture Notes",
    "Review",
    "Flashcards",
]
COURSE_WEIGHTS = [0.26, 0.22, 0.22, 0.16, 0.14]
ACTIVITY_WEIGHTS = [0.28, 0.30, 0.16, 0.16, 0.10]
NOTES = [
    "Worked through the problem set.",
    "Office hours follow-up.",
    "Caught up on lecture recordings.",
    "Reviewed for quiz.",
    "Group study in the library.",
    "Mostly reread notes.",
]

PACIFIC = timezone(timedelta(hours=-7))


def iso(dt: datetime) -> str:
    return dt.astimezone(PACIFIC).replace(microsecond=0).isoformat()


def split_durations(total: int, parts: int, rng: random.Random) -> list[int]:
    if parts <= 1:
        return [total]
    cuts = sorted(rng.sample(range(1, total), parts - 1))
    bounds = [0] + cuts + [total]
    return [bounds[i + 1] - bounds[i] for i in range(parts)]


def build_session(
    rng: random.Random,
    day: datetime,
    course: str,
    start_hour: int,
    start_minute: int,
    study_seconds: int,
) -> dict:
    start = day.replace(hour=start_hour, minute=start_minute, second=0)
    end = start + timedelta(seconds=study_seconds + rng.randint(60, 480))

    activity_count = 1 if rng.random() < 0.55 else (2 if rng.random() < 0.75 else 3)
    durations = split_durations(study_seconds, activity_count, rng)
    names = rng.sample(ACTIVITIES, k=min(activity_count, len(ACTIVITIES)))
    if len(names) < activity_count:
        names += rng.choices(ACTIVITIES, weights=ACTIVITY_WEIGHTS, k=activity_count - len(names))

    cursor = start
    activities = []
    for name, duration in zip(names, durations):
        activities.append(
            {
                "name": name,
                "start_time": iso(cursor),
                "duration_seconds": duration,
            }
        )
        cursor += timedelta(seconds=duration)

    record = {
        "term": TERM,
        "course": course,
        "start_time": iso(start),
        "end_time": iso(end),
        "study_time_seconds": study_seconds,
        "activities": activities,
    }
    if rng.random() < 0.35:
        record["note"] = rng.choice(NOTES)
    if rng.random() < 0.8:
        record["focus_rating"] = rng.randint(3, 5) if rng.random() < 0.7 else rng.randint(1, 5)
    return record


def generate(days: int, seed: int) -> list[dict]:
    rng = random.Random(seed)
    today = datetime.now(PACIFIC).replace(hour=0, minute=0, second=0, microsecond=0)
    records: list[dict] = []
    course_minutes = {name: 0 for name in COURSES}

    for offset in range(days - 1, -1, -1):
        day = today - timedelta(days=offset)
        weekday = day.weekday()  # Mon=0
        # Keep most days active so charts unlock; skip a couple of light days.
        if offset not in (0, days - 1) and weekday == 6 and rng.random() < 0.45:
            continue
        if offset not in (0, days - 1) and weekday == 5 and rng.random() < 0.2:
            continue

        session_count = 1
        if weekday < 5:
            session_count = rng.choice([1, 1, 2, 2, 3])
        else:
            session_count = rng.choice([1, 1, 2])

        used_hours: list[int] = []
        for _ in range(session_count):
            start_hour = rng.choice([8, 9, 10, 11, 13, 14, 15, 16, 18, 19, 20])
            if start_hour in used_hours:
                start_hour = min(21, start_hour + 2)
            used_hours.append(start_hour)

            lagging = min(COURSES, key=lambda c: course_minutes[c])
            course = lagging if rng.random() < 0.45 else rng.choices(COURSES, weights=COURSE_WEIGHTS, k=1)[0]

            # Default daily goal is 2h; mix of days above and below that.
            minutes = rng.choice([35, 45, 50, 60, 75, 90, 105, 120, 135])
            study_seconds = minutes * 60
            course_minutes[course] += minutes
            records.append(
                build_session(rng, day, course, start_hour, rng.choice([0, 5, 10, 15, 30, 45]), study_seconds)
            )

    records.sort(key=lambda r: r["start_time"])
    return records


def main() -> None:
    parser = argparse.ArgumentParser(description="Generate fake JSONL study data for import.")
    parser.add_argument("--days", type=int, default=16, help="Calendar days ending today (default 16).")
    parser.add_argument("--seed", type=int, default=13)
    parser.add_argument(
        "--out",
        type=Path,
        default=Path(__file__).resolve().parent.parent / "samples" / "fake-study-data.json",
    )
    args = parser.parse_args()
    if args.days < 8:
        parser.error("--days must be at least 8 so charts can unlock")

    records = generate(args.days, args.seed)
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text("".join(json.dumps(r, separators=(",", ":")) + "\n" for r in records), encoding="utf-8")

    courses = sorted({r["course"] for r in records})
    days = sorted({r["start_time"][:10] for r in records})
    print(f"Wrote {len(records)} sessions to {args.out}")
    print(f"Courses ({len(courses)}): {', '.join(courses)}")
    print(f"Study days: {len(days)} ({days[0]} → {days[-1]})")


if __name__ == "__main__":
    main()

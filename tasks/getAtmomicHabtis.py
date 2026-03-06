import os
import re
import json
from datetime import datetime
from typing import Dict, Any, Tuple, List, Optional

from groq import Groq
from config.constants import ATOMIC_HABITS

DEFAULT_MODEL = "openai/gpt-oss-120b"
ATOMIC_HABITS_FILE = ATOMIC_HABITS


# ----------------- Helpers -----------------
def normalize_key(text: str) -> str:
    text = text.strip().lower()
    text = re.sub(r"[^a-z0-9\s]+", "", text)
    text = re.sub(r"\s+", " ", text)
    return text


def load_json(path: str, default: Any) -> Any:
    if not os.path.exists(path):
        return default
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def save_json(path: str, data: Any) -> None:
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)


def load_habits_list(path: str) -> Dict[Any]:
    data = load_json(path, default=[])
    return data


def save_habits_list(path: str, habits: List[str]) -> None:
    deduped = []
    seen = set()
    for habit in habits:
        clean = str(habit).strip()
        key = normalize_key(clean)
        if clean and key not in seen:
            deduped.append(clean)
            seen.add(key)
    save_json(path, deduped)


# ----------------- LLM -----------------
def llm_match_or_create_habit(
    client: Groq,
    model: str,
    title: str,
    habits: List[str],
) -> Dict[str, str]:
    """
    Returns STRICT JSON:
    {
      "matched": true/false,
      "atomic_habit": "..."
    }
    """
    system = (
        "You assign a task title to the best matching atomic habit from a provided list.\n"
        "Rules:\n"
        "- If one existing habit clearly fits, return it exactly as written.\n"
        "- If none fit, create a new atomic habit.\n"
        "- A new atomic habit must be concrete, reusable, start with a verb, and be <= 6 words.\n"
        "- Remove dates, places, and one-off details.\n"
        "Return STRICT JSON only."
    )

    habits_text = json.dumps(habits, ensure_ascii=False)

    user = (
        f"Task title: {title}\n\n"
        f"Existing habits:\n{habits_text}\n\n"
        "Output schema:\n"
        '{ "matched": true, "atomic_habit": "one of the existing habits exactly" }\n'
        "or\n"
        '{ "matched": false, "atomic_habit": "new habit" }'
    )

    resp = client.chat.completions.create(
        model=model,
        messages=[
            {"role": "system", "content": system},
            {"role": "user", "content": user},
        ],
        response_format={"type": "json_object"},
        temperature=0.2,
    )

    data = json.loads(resp.choices[0].message.content)
    matched = bool(data.get("matched", False))
    atomic_habit = str(data.get("atomic_habit", "")).strip()

    if not atomic_habit:
        atomic_habit = title[:60].strip()

    return {
        "matched": matched,
        "atomic_habit": atomic_habit,
    }


def find_existing_habit_case_insensitive(habits: List[str], candidate: str) -> Optional[str]:
    candidate_key = normalize_key(candidate)
    for habit in habits:
        if normalize_key(habit) == candidate_key:
            return habit
    return None


# ----------------- Pipeline -----------------
def update_tracker(payload: Dict[str, Any], model: str = DEFAULT_MODEL) -> Tuple[Any, List[str]]:
    api_key = os.getenv("GROQ_API_KEY")
    if not api_key:
        raise RuntimeError("Missing GROQ_API_KEY environment variable")

    client = Groq(api_key=api_key)
    habits_json = load_habits_list(ATOMIC_HABITS_FILE)
    habits_list=habits_json['habits']

    for goal_list_name, tasks in payload.items():
        if not isinstance(tasks, list):
            continue

        for t in tasks:
            title = str(t.get("title", "")).strip()
            if not title:
                continue

            existing_atomic = str(t.get("atomic_habit", "")).strip()
            if existing_atomic:
                chosen_habit = existing_atomic
            else:
                result = llm_match_or_create_habit(
                    client=client,
                    model=model,
                    title=title,
                    habits=habits_list,
                )

                suggested_habit = result["atomic_habit"]
                matched_habit = find_existing_habit_case_insensitive(habits_list, suggested_habit)

                if matched_habit:
                    chosen_habit = matched_habit
                else:
                    chosen_habit = suggested_habit
                    habits_list.append(chosen_habit)

            t["atomic_habit"] = chosen_habit

    save_habits_list(ATOMIC_HABITS_FILE, habits_list)
    return payload, habits_list


def main(payload):
    enriched = update_tracker(payload)
    return enriched
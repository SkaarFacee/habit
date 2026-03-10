import os
import re
import json
import copy
from typing import Dict, Any, Tuple, List, Optional, Iterable

from groq import Groq
from config.constants import ATOMIC_HABITS

DEFAULT_MODEL = "openai/gpt-oss-120b"
ATOMIC_HABITS_FILE = ATOMIC_HABITS

# ----------------- Helpers -----------------
def normalize_key(text: str) -> str:
    text = str(text).strip().lower()
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


def load_habits_data(path: str) -> Dict[str, List[str]]:
    """
    Supports:
    {
        "habits": [...],
        "favorites": [...]
    }

    Also tolerates older plain-list format for backward compatibility.
    """
    data = load_json(path, default={"habits": [], "favorites": []})

    if isinstance(data, dict):
        habits = [str(x).strip() for x in data.get("habits", []) if str(x).strip()]
        favorites = [str(x).strip() for x in data.get("favorites", []) if str(x).strip()]
        return {
            "habits": habits,
            "favorites": favorites,
        }

    if isinstance(data, list):
        habits = [str(x).strip() for x in data if str(x).strip()]
        return {
            "habits": habits,
            "favorites": [],
        }

    return {
        "habits": [],
        "favorites": [],
    }


def save_habits_data(path: str, habits: List[str], favorites: Optional[List[str]] = None) -> None:
    """
    Saves while preserving the JSON structure:
    {
        "habits": [...],
        "favorites": [...]
    }
    """
    deduped_habits = []
    seen = set()
    for habit in habits:
        clean = str(habit).strip()
        key = normalize_key(clean)
        if clean and key not in seen:
            deduped_habits.append(clean)
            seen.add(key)

    deduped_favorites = []
    seen_fav = set()
    for fav in (favorites or []):
        clean = str(fav).strip()
        key = normalize_key(clean)
        if clean and key not in seen_fav:
            deduped_favorites.append(clean)
            seen_fav.add(key)

    save_json(
        path,
        {
            "habits": deduped_habits,
            "favorites": deduped_favorites,
        },
    )


def find_existing_habit_case_insensitive(habits: List[str], candidate: str) -> Optional[str]:
    candidate_key = normalize_key(candidate)
    for habit in habits:
        if normalize_key(habit) == candidate_key:
            return habit
    return None


def clean_notes(notes: Any) -> str:
    text = str(notes or "").strip()
    if normalize_key(text) in {"", "none", "null", "na", "n a", "nil"}:
        return ""
    return text


def iter_task_lists(payload: Dict[str, Any]) -> Iterable[Tuple[str, List[Dict[str, Any]]]]:
    """
    Supports only this payload shape:
    {
      "Daily Goals": [ {...}, {...} ],
      "Another List": [ {...} ]
    }
    """
    for list_name, tasks in payload.items():
        if isinstance(list_name, str) and isinstance(tasks, list):
            yield list_name, tasks


# ----------------- LLM -----------------
def llm_match_or_create_habit(
    client: Groq,
    model: str,
    title: str,
    notes: str,
    habits: List[str],
    favorites: List[str],
) -> Dict[str, str]:
    """
    Returns STRICT JSON:
    {
      "matched": true/false,
      "atomic_habit": "..."
    }
    """
    system = (
        "You assign a task to the best matching atomic habit from a provided list.\n"
        "Rules:\n"
        "- Use BOTH title and notes.\n"
        "- If notes clearly suggest one of the existing habits, choose that exact habit.\n"
        "- Prefer an existing habit over creating a new one.\n"
        "- Favorites are slightly preferred when they are a good fit, but do not force them.\n"
        "- If one existing habit clearly fits, return it exactly as written.\n"
        "- Only create a new atomic habit if none of the existing habits fit.\n"
        "- A new atomic habit must be concrete, reusable, start with a verb if possible, and be <= 6 words.\n"
        "- Remove dates, places, quantities, and one-off details.\n"
        "- Never invent a habit if an existing one is a reasonable fit.\n"
        "Return STRICT JSON only."
    )

    user = (
        f"Task title: {title}\n"
        f"Task notes: {notes or 'None'}\n\n"
        f"Existing habits:\n{json.dumps(habits, ensure_ascii=False)}\n\n"
        f"Favorite habits:\n{json.dumps(favorites, ensure_ascii=False)}\n\n"
        "Important:\n"
        "- If the notes suggest one of the existing habits, choose that exact habit.\n"
        "- Return the habit exactly as written from the existing list when matched.\n\n"
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
        temperature=0.1,
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


# ----------------- Pipeline -----------------
def update_tracker(payload: Dict[str, Any], model: str = DEFAULT_MODEL) -> Tuple[Dict[str, Any], List[str]]:
    api_key = os.getenv("GROQ_API_KEY")
    if not api_key:
        raise RuntimeError("Missing GROQ_API_KEY environment variable")

    client = Groq(api_key=api_key)

    # Work on a copy so we return a newly modified payload JSON
    new_payload = copy.deepcopy(payload)

    # Load habits data
    habits_data = load_habits_data(ATOMIC_HABITS_FILE)
    habits_list = list(habits_data["habits"])
    favorites = list(habits_data["favorites"])

    for _, tasks in iter_task_lists(new_payload):
        for t in tasks:
            if not isinstance(t, dict):
                continue

            title = str(t.get("title", "")).strip()
            notes = clean_notes(t.get("notes", ""))

            if not title:
                continue

            # Safe fallback in case atomic_habit appears in the future
            existing_atomic = str(t.get("atomic_habit", "")).strip()

            if existing_atomic:
                matched_habit = find_existing_habit_case_insensitive(habits_list, existing_atomic)
                chosen_habit = matched_habit if matched_habit else existing_atomic

                if not matched_habit:
                    habits_list.append(chosen_habit)
            else:
                result = llm_match_or_create_habit(
                    client=client,
                    model=model,
                    title=title,
                    notes=notes,
                    habits=habits_list,
                    favorites=favorites,
                )

                suggested_habit = result["atomic_habit"]
                matched_habit = find_existing_habit_case_insensitive(habits_list, suggested_habit)

                if matched_habit:
                    chosen_habit = matched_habit
                else:
                    chosen_habit = suggested_habit
                    habits_list.append(chosen_habit)

            t["atomic_habit"] = chosen_habit

    # Uncomment this if you want to persist new habits to the file
    # save_habits_data(ATOMIC_HABITS_FILE, habits_list, favorites)

    return new_payload, list(habits_list)


def main(payload: Dict[str, Any]) -> Tuple[Dict[str, Any], List[str]]:
    updated_payload, updated_habits = update_tracker(payload)
    return updated_payload, updated_habits
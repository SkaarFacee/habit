import os
import re
import json
import copy
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


def load_habits_list(path: str) -> List[str]:
    data = load_json(path, default=[])
    if isinstance(data, dict):
        return [str(x).strip() for x in data['habits'] if str(x).strip()]
    return []


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

def find_existing_habit_case_insensitive(habits: List[str], candidate: str) -> Optional[str]:
    candidate_key = normalize_key(candidate)
    for habit in habits:
        if normalize_key(habit) == candidate_key:
            return habit
   

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


# ----------------- Pipeline -----------------
def update_tracker(payload: Dict[str, Any], model: str = DEFAULT_MODEL) -> Tuple[Dict[str, Any], List[str]]:
    api_key = os.getenv("GROQ_API_KEY")
    if not api_key:
        raise RuntimeError("Missing GROQ_API_KEY environment variable")

    client = Groq(api_key=api_key)

    # Work on a copy so we return a newly modified payload JSON
    new_payload = copy.deepcopy(payload)

    # Load habits and make sure we return a brand-new list object
    habits_list = list(load_habits_list(ATOMIC_HABITS_FILE))

    tracker = new_payload.get("Tracker", {})
    list_names = new_payload.get("lists", [])

    if not isinstance(tracker, dict):
        raise ValueError("payload['Tracker'] must be a dictionary")

    if not isinstance(list_names, list):
        raise ValueError("payload['lists'] must be a list")

    # IMPORTANT:
    # list names are case-sensitive, so use them exactly as they appear
    # in payload["lists"] without normalizing/changing case.
    for list_name in list_names:
        if not isinstance(list_name, str):
            continue

        dated_tasks = tracker.get(list_name)
        if not isinstance(dated_tasks, dict):
            continue

        for date_key, tasks in dated_tasks.items():
            if not isinstance(tasks, list):
                continue

            for t in tasks:
                if not isinstance(t, dict):
                    continue

                title = str(t.get("title", "")).strip()
                if not title:
                    continue

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

    # save_habits_list(ATOMIC_HABITS_FILE, habits_list)
    return new_payload, list(habits_list)


def main(payload):
    updated_payload, updated_habits = update_tracker(payload)
    print("This is the output of the update habits ")
    print(updated_habits)
    return updated_payload, updated_habits
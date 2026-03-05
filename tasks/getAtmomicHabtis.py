import os
import re
import json
import csv
from datetime import datetime
from typing import Dict, Any, Optional, Tuple, List
from sentence_transformers import SentenceTransformer
from config.constants import GROQ_API_LABEL


import numpy as np
from groq import Groq

DEFAULT_MODEL = "openai/gpt-oss-120b"


EMBED_MODEL = "all-MiniLM-L6-v2"
embedding_model = SentenceTransformer(EMBED_MODEL)
ATOMIC_HABITS_FILE = "atomic_habits.json"
ATOMIC_HABIT_EMBEDDINGS_FILE = "atomic_habit_embeddings.json"  # key -> embedding vector




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

def cosine_similarity(a, b) -> float:
    a = np.asarray(a, dtype=np.float32)
    b = np.asarray(b, dtype=np.float32)
    return float(np.dot(a, b))

# ----------------- Embeddings -----------------
def embed_text(text: str):
    if not text:
        return None
    vec= embedding_model.encode(text, normalize_embeddings=True)
    return vec.tolist()

def ensure_habit_embedding(habit_key: str, habit_name: str, embeddings_store: Dict[str, Any]) -> None:
    if habit_key in embeddings_store:
        # also repair legacy ndarray values if present
        v = embeddings_store[habit_key]
        if hasattr(v, "tolist"):
            embeddings_store[habit_key] = v.tolist()
        return

    emb = embed_text(habit_name)
    if emb is not None:
        embeddings_store[habit_key] = emb


def build_embedding_index(
    embeddings_store: Dict[str, Any],
) -> Tuple[List[str], np.ndarray]:
    """
    Returns (habit_keys, matrix[n,d]) for fast cosine similarity search.
    """
    keys = []
    vecs = []
    for k, v in embeddings_store.items():
        if isinstance(v, list) and len(v) > 0:
            keys.append(k)
            vecs.append(v)
    if not vecs:
        return [], np.zeros((0, 0), dtype=np.float32)
    mat = np.array(vecs, dtype=np.float32)
    return keys, mat


def match_existing_habit_by_embedding(title, habits_store, embeddings_store, threshold=0.75):

    title_vec = embed_text(title)

    best_key = None
    best_score = -1

    for habit_key, habit_obj in habits_store.items():

        if habit_key not in embeddings_store:
            embeddings_store[habit_key] = embed_text(habit_obj["atomic_habit"])

        score = cosine_similarity(title_vec, embeddings_store[habit_key])

        if score > best_score:
            best_score = score
            best_key = habit_key

    if best_score >= threshold:
        return best_key, habits_store[best_key], best_score

    return None

# ----------------- LLM: title -> atomic habit ONLY -----------------
def llm_parse_atomic_habit_only(client: Groq, model: str, title: str) -> Dict[str, str]:
    """
    Returns STRICT JSON:
    { "atomic_habit": "Verb + object, single action, <= 6 words" }
    """
    system = (
        "You convert task titles into a single atomic habit.\n"
        "Rules:\n"
        "- atomic_habit: one concrete action, starts with a verb, <= 6 words.\n"
        "- Make it reusable; remove places/times.\n"
        "Return STRICT JSON only."
    )

    user = (
        f"Task title: {title}\n\n"
        'Output schema:\n'
        '{ "atomic_habit": "..." }'
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
    atomic_habit = str(data.get("atomic_habit", "")).strip()
    if not atomic_habit:
        atomic_habit = title[:60]
    return {"atomic_habit": atomic_habit}


# ----------------- Pipeline -----------------
def update_tracker(payload: Dict[str, Any], model: str = DEFAULT_MODEL) -> Dict[str, Any]:
    api_key = os.getenv("GROQ_API_KEY")
    if not api_key:
        raise RuntimeError("Missing GROQ_API_KEY environment variable")

    client = Groq(api_key=api_key)

    habits_store: Dict[str, Any] = load_json(ATOMIC_HABITS_FILE, default={})
    embeddings_store: Dict[str, Any] = load_json(ATOMIC_HABIT_EMBEDDINGS_FILE, default={})


    today = datetime.now().strftime("%Y-%m-%d")

    for goal_list_name, tasks in payload.items():
        if not isinstance(tasks, list):
            continue

        for t in tasks:
            title = str(t.get("title", "")).strip()
            if not title:
                continue

            status = str(t.get("status", "")).strip()
            completed_on = str(t.get("completed", "")).strip()

            # If already present, keep it (optional behavior)
            existing_atomic = str(t.get("atomic_habit", "")).strip()
            if existing_atomic:
                chosen_habit = existing_atomic
                habit_key = normalize_key(chosen_habit)
                match_sim = ""
            else:
                # 1) embedding match against existing habits
                matched = match_existing_habit_by_embedding(
                    title,
                    habits_store,
                    embeddings_store,
                    threshold=0.86,  # tune this: 0.82-0.90 typical
                )

                if matched:
                    habit_key, habit_obj, sim = matched
                    chosen_habit = str(habit_obj.get("atomic_habit", title)).strip() or title
                    match_sim = f"{sim:.3f}"
                else:
                    # 2) no match -> create new habit via LLM
                    parsed = llm_parse_atomic_habit_only(client, model=model, title=title)
                    chosen_habit = parsed["atomic_habit"]
                    habit_key = normalize_key(chosen_habit)
                    match_sim = ""

                    if habit_key not in habits_store:
                        habits_store[habit_key] = {
                            "atomic_habit": chosen_habit,
                            "created_at": datetime.utcnow().isoformat(timespec="seconds") + "Z",
                        }

                    # store embedding for the new habit
                    ensure_habit_embedding(habit_key, chosen_habit, embeddings_store)

            # ✅ write back into the task
            t["atomic_habit"] = chosen_habit


    save_json(ATOMIC_HABITS_FILE, habits_store)

    for k, v in list(embeddings_store.items()):
        if hasattr(v, "tolist"):        # numpy array or similar
            embeddings_store[k] = v.tolist()
    save_json(ATOMIC_HABIT_EMBEDDINGS_FILE, embeddings_store)

    return payload

def main(payload):
    enriched = update_tracker(payload)
    return enriched
    # print(json.dumps(enriched, indent=2, ensure_ascii=False))
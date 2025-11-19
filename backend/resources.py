import json
from pathlib import Path

base_path = Path(__file__).parent / "data"

def load_json(name):
    path = base_path / name
    try:
        with open(path, "r", encoding="utf-8") as f:
            return json.load(f)
    except FileNotFoundError:
        return {}
    except json.JSONDecodeError:
        return {}

linkedin = load_json("linkedin.json")
summary = load_json("summary.json")
facts = load_json("facts.json")
style = load_json("style.json")

import os
import json

BASE_DIR = os.path.dirname(__file__)
DATA_DIR = os.path.join(BASE_DIR, "data")

# Load facts
facts_path = os.path.join(DATA_DIR, "facts.json")
try:
    with open(facts_path, "r", encoding="utf-8") as f:
        facts = json.load(f)
except FileNotFoundError:
    raise RuntimeError(f"Facts file not found at {facts_path}")

# Placeholder modules
linkedin = {}
summary = {}
style = {}

from pypdf import PdfReader
import json
import os

# Base directory: directory where this file lives
BASE_DIR = os.path.dirname(__file__)
DATA_DIR = os.path.join(BASE_DIR, "data")

# Read LinkedIn PDF
linkedin_path = os.path.join(DATA_DIR, "linkedin.pdf")
linkedin = ""

try:
    reader = PdfReader(linkedin_path)
    for page in reader.pages:
        text = page.extract_text()
        if text:
            linkedin += text
except FileNotFoundError:
    linkedin = "LinkedIn profile not available"

# Read summary
summary_path = os.path.join(DATA_DIR, "summary.txt")
with open(summary_path, "r", encoding="utf-8") as f:
    summary = f.read()

# Read style notes
style_path = os.path.join(DATA_DIR, "style.txt")
with open(style_path, "r", encoding="utf-8") as f:
    style = f.read()

# Read facts
facts_path = os.path.join(DATA_DIR, "facts.json")
with open(facts_path, "r", encoding="utf-8") as f:
    facts = json.load(f)

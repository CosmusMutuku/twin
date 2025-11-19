import os
import shutil
import subprocess
from pathlib import Path

BASE_DIR = Path(__file__).parent.resolve()
BACKEND_DIR = BASE_DIR / "backend"
PACKAGE_DIR = BACKEND_DIR / "lambda-package"
ZIP_FILE = BACKEND_DIR / "lambda-package.zip"

# Clean package directory
shutil.rmtree(PACKAGE_DIR, ignore_errors=True)
if ZIP_FILE.exists():
    ZIP_FILE.unlink()
PACKAGE_DIR.mkdir(parents=True, exist_ok=True)

# Install dependencies
subprocess.run(
    ["pip", "install", "--upgrade", "pip"],
    check=True
)
subprocess.run(
    ["pip", "install", "-r", str(BACKEND_DIR / "requirements.txt"), "--target", str(PACKAGE_DIR)],
    check=True
)

# Copy source files
for f in ["server.py", "lambda_handler.py", "context.py", "resources.py"]:
    shutil.copy(BACKEND_DIR / f, PACKAGE_DIR / f)

# Copy data folder
data_dir = BACKEND_DIR / "data"
if not data_dir.exists():
    raise FileNotFoundError("data/ folder not found")
shutil.copytree(data_dir, PACKAGE_DIR / "data")

# Create ZIP
subprocess.run(["zip", "-r", str(ZIP_FILE), "."], cwd=PACKAGE_DIR, check=True)

# Deploy via Terraform
subprocess.run(["terraform", "apply", "-auto-approve"], cwd=BASE_DIR / "terraform", check=True)

print("✅ Deployment complete!")

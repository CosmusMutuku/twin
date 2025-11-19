import os
import shutil
import zipfile
import subprocess

def main():
    print("Creating Lambda deployment package...")

    PROJECT_ROOT = os.path.dirname(os.path.abspath(__file__))  # backend/
    PACKAGE_DIR = os.path.join(PROJECT_ROOT, "lambda-package")
    DEPLOY_ZIP = os.path.join(PROJECT_ROOT, "lambda-deployment.zip")
    DATA_DIR = os.path.join(PROJECT_ROOT, "data")

    # Clean up
    if os.path.exists(PACKAGE_DIR):
        shutil.rmtree(PACKAGE_DIR)
    if os.path.exists(DEPLOY_ZIP):
        os.remove(DEPLOY_ZIP)

    os.makedirs(PACKAGE_DIR)

    # Install dependencies inside Lambda runtime container
    print("Installing dependencies for Lambda runtime...")
    subprocess.run(
        [
            "docker", "run", "--rm",
            "-v", f"{PROJECT_ROOT}:/var/task",
            "--platform", "linux/amd64",
            "--entrypoint", "",
            "public.ecr.aws/lambda/python:3.12",
            "/bin/sh", "-c",
            "pip install --target /var/task/lambda-package "
            "-r /var/task/requirements.txt "
            "--platform manylinux2014_x86_64 "
            "--only-binary=:all: --upgrade"
        ],
        check=True,
    )

    # Copy application files
    print("Copying application files...")
    for file in ["server.py", "lambda_handler.py", "context.py", "resources.py"]:
        src_file = os.path.join(PROJECT_ROOT, file)
        if os.path.exists(src_file):
            shutil.copy2(src_file, PACKAGE_DIR)

    # Copy data directory
    if os.path.exists(DATA_DIR):
        shutil.copytree(DATA_DIR, os.path.join(PACKAGE_DIR, "data"))

    # Zip the package
    print("Creating zip file...")
    with zipfile.ZipFile(DEPLOY_ZIP, "w", zipfile.ZIP_DEFLATED) as zipf:
        for root, dirs, files in os.walk(PACKAGE_DIR):
            for file in files:
                file_path = os.path.join(root, file)
                arcname = os.path.relpath(file_path, PACKAGE_DIR)
                zipf.write(file_path, arcname)

    size_mb = os.path.getsize(DEPLOY_ZIP) / (1024 * 1024)
    print(f"✓ Created lambda-deployment.zip ({size_mb:.2f} MB)")


if __name__ == "__main__":
    main()



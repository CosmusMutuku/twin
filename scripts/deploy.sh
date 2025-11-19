#!/bin/bash

set -e
set -o pipefail

# Go to backend folder (where requirements.txt and source files live)
cd "$(dirname "$0")/../backend"

PACKAGE_DIR="lambda-package"
ZIP_FILE="lambda-package.zip"

echo "===> Cleaning package directory"
rm -rf "$PACKAGE_DIR" "$ZIP_FILE"
mkdir -p "$PACKAGE_DIR"

echo "===> Installing dependencies"
pip install --upgrade pip > /dev/null
pip install -r requirements.txt --target "$PACKAGE_DIR" > /dev/null

echo "===> Copying source files"
cp server.py "$PACKAGE_DIR"
cp lambda_handler.py "$PACKAGE_DIR"
cp context.py "$PACKAGE_DIR"
cp resources.py "$PACKAGE_DIR"

echo "===> Copying data folder"
if [ ! -d "data" ]; then
    echo "❌ ERROR: data/ folder not found!"
    exit 1
fi
cp -r data "$PACKAGE_DIR/data"

echo "===> Creating ZIP package"
cd "$PACKAGE_DIR"
zip -r "../$ZIP_FILE" . > /dev/null
cd ..

echo "===> Deploying via Terraform"
cd ../terraform
terraform apply -auto-approve

echo "===> Deployment complete!"

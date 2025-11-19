# 


#!/bin/bash
set -e

ENVIRONMENT=${1:-dev}          # dev | test | prod
PROJECT_NAME=${2:-twin}

echo "🚀 Deploying ${PROJECT_NAME} to ${ENVIRONMENT}..."

# 0. Ensure backend build directory is clean
cd "$(dirname "$0")/.."
echo "🧹 Cleaning old Lambda builds..."
rm -rf backend/lambda-package
rm -f backend/lambda-deployment.zip

# 1. Build Lambda package
echo "📦 Building Lambda package..."
(cd backend && uv run deploy.py)

# 1a. Verify ZIP contents
echo "📄 Lambda ZIP contents:"
# Use unzip if available (Linux/WSL), fallback to PowerShell on Windows runners
if command -v unzip &> /dev/null; then
    unzip -l backend/lambda-deployment.zip
else
    powershell -Command "Add-Type -AssemblyName System.IO.Compression.FileSystem; [System.IO.Compression.ZipFile]::OpenRead('backend/lambda-deployment.zip').Entries | ForEach-Object { $_.FullName }"
fi

# 2. Terraform workspace & apply
cd terraform
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
AWS_REGION=${DEFAULT_AWS_REGION:-eu-west-1}

terraform init -input=false \
  -backend-config="bucket=twin-terraform-state-${AWS_ACCOUNT_ID}" \
  -backend-config="key=${ENVIRONMENT}/terraform.tfstate" \
  -backend-config="region=${AWS_REGION}" \
  -backend-config="dynamodb_table=twin-terraform-locks" \
  -backend-config="encrypt=true"

if ! terraform workspace list | grep -q "$ENVIRONMENT"; then
  terraform workspace new "$ENVIRONMENT"
else
  terraform workspace select "$ENVIRONMENT"
fi

if [ "$ENVIRONMENT" = "prod" ]; then
  TF_APPLY_CMD=(terraform apply -var-file=prod.tfvars -var="project_name=$PROJECT_NAME" -var="environment=$ENVIRONMENT" -auto-approve)
else
  TF_APPLY_CMD=(terraform apply -var="project_name=$PROJECT_NAME" -var="environment=$ENVIRONMENT" -auto-approve)
fi

echo "🎯 Applying Terraform..."
"${TF_APPLY_CMD[@]}"

API_URL=$(terraform output -raw api_gateway_url)
FRONTEND_BUCKET=$(terraform output -raw s3_frontend_bucket)
CUSTOM_URL=$(terraform output -raw custom_domain_url 2>/dev/null || true)

# 3. Build + deploy frontend
cd ../frontend
echo "📝 Setting API URL for production..."
echo "NEXT_PUBLIC_API_URL=$API_URL" > .env.production

npm install
npm run build
aws s3 sync ./out "s3://$FRONTEND_BUCKET/" --delete
cd ..

# 4. Final messages
echo -e "\n✅ Deployment complete!"
echo "🌐 CloudFront URL : $(terraform -chdir=terraform output -raw cloudfront_url)"
if [ -n "$CUSTOM_URL" ]; then
  echo "🔗 Custom domain  : $CUSTOM_URL"
fi
echo "📡 API Gateway    : $API_URL"

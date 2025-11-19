#!/bin/bash
set -e

########################################
# 0. Parameters
########################################
ENVIRONMENT=${1:-dev}   # dev | test | prod
PROJECT_NAME=${2:-twin}

echo "🚀 Deploying ${PROJECT_NAME} to ${ENVIRONMENT}..."

########################################
# 1. Build Lambda package
########################################
cd "$(dirname "$0")/.."  # project root

echo "📦 Building Lambda package..."
(cd backend && uv run deploy.py)

LAMBDA_ZIP_PATH="backend/lambda-deployment.zip"
if [ ! -f "$LAMBDA_ZIP_PATH" ]; then
    echo "❌ Lambda package not found at $LAMBDA_ZIP_PATH"
    exit 1
fi

echo "📦 Lambda deployment package created at $LAMBDA_ZIP_PATH"
echo "🔍 Lambda package contents:"
unzip -l "$LAMBDA_ZIP_PATH" | grep -E "data/|\.py$"

########################################
# 2. Terraform workspace & apply
########################################
cd terraform

AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
AWS_REGION=${DEFAULT_AWS_REGION:-eu-west-1}

terraform init -input=false \
  -backend-config="bucket=twin-terraform-state-${AWS_ACCOUNT_ID}" \
  -backend-config="key=${ENVIRONMENT}/terraform.tfstate" \
  -backend-config="region=${AWS_REGION}" \
  -backend-config="dynamodb_table=twin-terraform-locks" \
  -backend-config="encrypt=true"

# Workspace handling
if ! terraform workspace list | grep -q "$ENVIRONMENT"; then
  terraform workspace new "$ENVIRONMENT"
else
  terraform workspace select "$ENVIRONMENT"
fi

# Apply Terraform
if [ "$ENVIRONMENT" = "prod" ]; then
    TF_APPLY_CMD=(terraform apply -var-file=prod.tfvars -var="project_name=$PROJECT_NAME" -var="environment=$ENVIRONMENT" -auto-approve)
else
    TF_APPLY_CMD=(terraform apply -var="project_name=$PROJECT_NAME" -var="environment=$ENVIRONMENT" -auto-approve)
fi

echo "🎯 Applying Terraform..."
"${TF_APPLY_CMD[@]}"

API_URL=$(terraform output -raw api_gateway_url)
FRONTEND_BUCKET=$(terraform output -raw s3_frontend_bucket)

########################################
# 3. Build + deploy frontend (Next.js → S3)
########################################
cd ../frontend

echo "📝 Writing .env.production with API URL..."
echo "NEXT_PUBLIC_API_URL=$API_URL" > .env.production

echo "📦 Installing frontend dependencies..."
npm ci

echo "🏗️ Building Next.js static site..."
npm run build

echo "🪣 Uploading static site to S3 bucket: $FRONTEND_BUCKET"
aws s3 sync ./out/ "s3://$FRONTEND_BUCKET/" --delete

########################################
# 4. Final messages
########################################
cd ..

echo -e "\n✅ Deployment complete!"
echo "📡 API Gateway URL : $API_URL"
echo "🪣 Frontend Bucket : $FRONTEND_BUCKET"
echo "📦 Lambda package path : $LAMBDA_ZIP_PATH"

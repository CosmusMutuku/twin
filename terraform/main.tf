provider "aws" {
  region = var.region
}

terraform {
  backend "s3" {
    bucket         = "twin-terraform-state-dev"
    key            = "lambda-functions/terraform.tfstate"
    region         = "eu-west-1"
    dynamodb_table = "twin-terraform-state-lock"
  }
}

data "aws_caller_identity" "current" {}

# --- Variables -------------------------------------------------------------

variable "lambda_roles" {
  description = "IAM roles for Lambda functions"
  type = map(object({
    name                     = string
    policy_arns              = list(string)
    policies                 = list(string)
    external_policy_contents = list(string)
  }))
}

variable "bucket_names" {
  description = "S3 bucket names"
  type        = map(string)
}

variable "region" {
  description = "AWS region"
  type        = string
  default     = "eu-west-1"
}

variable "corp_api_url" {
  description = "Corporate API URL"
  type        = string
}

variable "product_name" {
  description = "Product name"
  type        = string
}

variable "consumer" {
  description = "Customer name"
  type        = string
}

# --- S3 Buckets -------------------------------------------------------------

resource "aws_s3_bucket" "frontend" {
  bucket = var.bucket_names["frontend"]
}

resource "aws_s3_bucket_website_configuration" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  index_document {
    suffix = "index.html"
  }

  error_document {
    key = "404.html"
  }
}

resource "aws_s3_bucket_public_access_block" "frontend" {
  bucket = aws_s3_bucket.frontend.id
}

resource "aws_s3_bucket_policy" "frontend" {
  bucket = aws_s3_bucket.frontend.id
  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowPublicRead",
      "Effect": "Allow",
      "Principal": "*",
      "Action": [
        "s3:GetObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::${var.bucket_names["frontend"]}",
        "arn:aws:s3:::${var.bucket_names["frontend"]}/*"
      ]
    }
  ]
}
EOF
}

# --- Lambda Roles -------------------------------------------------------------

resource "aws_iam_role" "lambda_role" {
  for_each = var.lambda_roles

  name = each.value.name

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

  inline_policy {
    name   = "${each.value.name}-inline"
    policy = jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Effect   = "Allow"
          Action   = ["s3:GetObject", "s3:ListBucket"]
          Resource = ["arn:aws:s3:::twin-dev-data", "arn:aws:s3:::twin-dev-data/*"]
        }
      ]
    })
  }

  managed_policy_arns = each.value.policy_arns

  dynamic "inline_policy" {
    for_each = each.value.policies
    content {
      name   = "${each.value.name}-${inline_policy.key}"
      policy = inline_policy.value
    }
  }

  dynamic "inline_policy" {
    for_each = each.value.external_policy_contents
    content {
      name   = "${each.value.name}-custom-${inline_policy.key}"
      policy = each.value.external_policy_contents[inline_policy.key]
    }
  }
}

# --- Lambda Functions ---------------------------------------------------------

resource "archive_file" "iam_lambda_package" {
  type        = "zip"
  source_file = "${path.module}/../scripts/iam-lambda.py"
  output_path = "${path.module}/iam-lambda.zip"
}

resource "archive_file" "backend_lambda_package" {
  type        = "zip"
  source_file = "${path.module}/../scripts/backend-lambda.py"
  output_path = "${path.module}/backend-lambda.zip"
}

resource "aws_lambda_function" "iam_lambda" {
  filename      = archive_file.iam_lambda_package.output_path
  function_name = "twin-dev-iam-lambda"
  role          = aws_iam_role.lambda_role["iam-lambda"].arn
  handler       = "iam-lambda.handler"
  runtime       = "python3.9"

  environment {
    variables = {
      REGION           = var.region
      CORP_API_URL     = var.corp_api_url
      PRODUCT_NAME     = var.product_name
      AWS_ACCOUNT_ID   = data.aws_caller_identity.current.account_id
    }
  }
}

resource "aws_lambda_function" "backend_lambda" {
  filename      = archive_file.backend_lambda_package.output_path
  function_name = "twin-dev-backend-lambda"
  role          = aws_iam_role.lambda_role["backend-lambda"].arn
  handler       = "backend-lambda.handler"
  runtime       = "python3.9"

  environment {
    variables = {
      REGION           = var.region
      CONSUMER         = var.consumer
      PRODUCT_NAME     = var.product_name
      CORPORATE_API    = var.corp_api_url
      CORS_ORIGINS     = "http://${aws_s3_bucket_website_configuration.frontend.website_endpoint}"
    }
  }
}

# --- Outputs ------------------------------------------------------------------

output "frontend_bucket" {
  value = var.bucket_names["frontend"]
}

output "frontend_url" {
  value = aws_s3_bucket_website_configuration.frontend.website_endpoint
}

output "iam_lambda_arn" {
  value = aws_lambda_function.iam_lambda.arn
}

output "backend_lambda_arn" {
  value = aws_lambda_function.backend_lambda.arn
}

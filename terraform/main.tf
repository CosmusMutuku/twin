terraform {
  required_version = ">= 1.5.0"

  backend "s3" {}
}

provider "aws" {
  region = var.aws_region
}

#############################
# Variables
#############################

variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "aws_region" {
  type    = string
  default = "us-east-1"
}

#############################
# S3 STATIC FRONTEND BUCKET
#############################

resource "aws_s3_bucket" "frontend" {
  bucket        = "${var.project_name}-frontend-${var.environment}"
  force_destroy = true   # <-- FIX: prevents GitHub Actions from failing

  tags = {
    Project     = var.project_name
    Environment = var.environment
  }
}

resource "aws_s3_bucket_website_configuration" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  index_document {
    suffix = "index.html"
  }

  error_document {
    key = "index.html"
  }
}

resource "aws_s3_bucket_public_access_block" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

# Correct public policy so React frontend loads
resource "aws_s3_bucket_policy" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "PublicReadGetObject"
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:GetObject"
        Resource  = "${aws_s3_bucket.frontend.arn}/*"
      }
    ]
  })
}

################################
# LAMBDA + IAM
################################

resource "aws_iam_role" "lambda_role" {
  name = "${var.project_name}-lambda-role-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = { Service = "lambda.amazonaws.com" }
        Action    = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_lambda_function" "api" {
  function_name = "${var.project_name}-api-${var.environment}"
  role          = aws_iam_role.lambda_role.arn
  handler       = "main.handler"
  runtime       = "python3.12"

  filename         = "${path.module}/../backend/lambda-deployment.zip"
  source_code_hash = filebase64sha256("${path.module}/../backend/lambda-deployment.zip")

  timeout = 30
}

################################
# API GATEWAY
################################

resource "aws_apigatewayv2_api" "http" {
  name          = "${var.project_name}-api-${var.environment}"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_integration" "lambda" {
  api_id                 = aws_apigatewayv2_api.http.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.api.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "root" {
  api_id    = aws_apigatewayv2_api.http.id
  route_key = "ANY /{proxy+}"
  target    = "integrations/${aws_apigatewayv2_integration.lambda.id}"
}

resource "aws_lambda_permission" "api_gateway" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.api.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.http.execution_arn}/*"
}

#############################
# Outputs
#############################

output "api_gateway_url" {
  value = aws_apigatewayv2_api.http.api_endpoint
}

output "s3_frontend_bucket" {
  value = aws_s3_bucket.frontend.id
}

output "frontend_url" {
  value = "http://${aws_s3_bucket.frontend.bucket}.s3-website-${var.aws_region}.amazonaws.com"
}

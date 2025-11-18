terraform {
  required_version = "~> 1.9"

  backend "s3" {
    bucket = "twin-terraform-state"
    key    = "dev/terraform.tfstate"
    region = "us-east-1"
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

###############################
# Lambda Execution Role
###############################

resource "aws_iam_role" "lambda_role" {
  name = "twin-lambda-role-dev"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

###############################
# API Lambda
###############################

resource "aws_lambda_function" "api" {
  function_name = "twin-api-dev"
  handler       = "lambda_handler.handler"
  runtime       = "python3.12"

  role          = aws_iam_role.lambda_role.arn
  filename      = "lambda-deployment.zip"
  source_code_hash = filebase64sha256("lambda-deployment.zip")
  timeout       = 30
}

###############################
# API Gateway (HTTP API)
###############################

resource "aws_apigatewayv2_api" "http" {
  name          = "twin-http-api-dev"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_integration" "lambda" {
  api_id           = aws_apigatewayv2_api.http.id
  integration_type = "AWS_PROXY"
  integration_uri  = aws_lambda_function.api.invoke_arn
}

resource "aws_apigatewayv2_route" "root" {
  api_id    = aws_apigatewayv2_api.http.id
  route_key = "ANY /"
  target    = "integrations/${aws_apigatewayv2_integration.lambda.id}"
}

resource "aws_lambda_permission" "api_gateway" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.api.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.http.execution_arn}/*/*"
}

###############################
# S3 Frontend Bucket
###############################

resource "aws_s3_bucket" "frontend" {
  bucket        = "twin-frontend-dev"
  force_destroy = true   # Ensures clean deletes (fixes BucketNotEmpty)
}

resource "aws_s3_bucket_public_access_block" "frontend" {
  bucket                  = aws_s3_bucket.frontend.id
  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

resource "aws_s3_bucket_policy" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = "*"
        Action   = "s3:GetObject"
        Resource = "${aws_s3_bucket.frontend.arn}/*"
      }
    ]
  })
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

###############################
# Outputs
###############################

output "frontend_bucket" {
  value = aws_s3_bucket.frontend.bucket
}

output "api_url" {
  value = aws_apigatewayv2_api.http.api_endpoint
}

#############################################
# AWS Provider
#############################################

provider "aws" {
  region = var.region != "" ? var.region : "us-east-1"
}

provider "aws" {
  alias  = "eu_west_1"
  region = "eu-west-1"
}

#############################################
# S3 Buckets (frontend + memory)
#############################################

resource "aws_s3_bucket" "frontend" {
  bucket = "${var.project_name}-${var.environment}-frontend"
}

resource "aws_s3_bucket" "memory" {
  bucket = "${var.project_name}-${var.environment}-memory"
}

#############################################
# IAM Role for Lambda
#############################################

resource "aws_iam_role" "lambda_exec" {
  name = "${var.project_name}-${var.environment}-lambda-role"

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
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

#############################################
# Lambda Function
#############################################

resource "aws_lambda_function" "api" {
  function_name = "${var.project_name}-${var.environment}-api"
  role          = aws_iam_role.lambda_exec.arn
  handler       = "lambda_handler.handler"
  runtime       = "python3.12"

  filename         = "lambda-deployment.zip"
  source_code_hash = filebase64sha256("lambda-deployment.zip")

  timeout = var.lambda_timeout

  environment {
    variables = {
      PROJECT_NAME  = var.project_name
      ENVIRONMENT   = var.environment
      BEDROCK_MODEL = var.bedrock_model_id
      MEMORY_BUCKET = aws_s3_bucket.memory.bucket

      # CORS ORIGINS FIXED (Terraform-safe)
      CORS_ORIGINS = var.use_custom_domain && var.root_domain != "" ?
        "https://${var.root_domain},https://www.${var.root_domain}" :
        "*"
    }
  }
}

#############################################
# API Gateway (HTTP API v2)
#############################################

resource "aws_apigatewayv2_api" "main" {
  name          = "${var.project_name}-${var.environment}-api"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_integration" "lambda" {
  api_id             = aws_apigatewayv2_api.main.id
  integration_type   = "AWS_PROXY"
  integration_uri    = aws_lambda_function.api.invoke_arn
  integration_method = "POST"
}

resource "aws_apigatewayv2_route" "proxy" {
  api_id    = aws_apigatewayv2_api.main.id
  route_key = "$default"
  target    = "integrations/${aws_apigatewayv2_integration.lambda.id}"
}

resource "aws_lambda_permission" "apigw" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.api.arn
  principal     = "apigateway.amazonaws.com"
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.main.id
  name        = "$default"
  auto_deploy = true

  default_route_settings {
    throttling_burst_limit = var.api_throttle_burst_limit
    throttling_rate_limit  = var.api_throttle_rate_limit
  }
}

#############################################
# CloudFront (optionally with custom domain)
#############################################

resource "aws_cloudfront_origin_access_control" "s3_oac" {
  name                              = "${var.project_name}-${var.environment}-oac"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_distribution" "main" {
  enabled = true

  origin {
    domain_name = aws_s3_bucket.frontend.bucket_regional_domain_name
    origin_id   = "frontend-s3"

    origin_access_control_id = aws_cloudfront_origin_access_control.s3_oac.id
  }

  default_cache_behavior {
    target_origin_id       = "frontend-s3"
    viewer_protocol_policy = "redirect-to-https"

    allowed_methods = ["GET", "HEAD"]
    cached_methods  = ["GET", "HEAD"]

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }
  }

  price_class = "PriceClass_100"

  viewer_certificate {
    cloudfront_default_certificate = var.use_custom_domain ? false : true
    acm_certificate_arn            = var.use_custom_domain ? aws_acm_certificate.main[0].arn : null
    minimum_protocol_version       = "TLSv1.2_2021"
  }

  aliases = var.use_custom_domain && var.root_domain != "" ?
    [var.root_domain, "www.${var.root_domain}"] :
    []
}

#############################################
# ACM Certificate (only when custom domain)
#############################################

resource "aws_acm_certificate" "main" {
  count = var.use_custom_domain && var.root_domain != "" ? 1 : 0

  domain_name       = var.root_domain
  validation_method = "DNS"

  subject_alternative_names = [
    "www.${var.root_domain}"
  ]

  provider = aws.eu_west_1
}


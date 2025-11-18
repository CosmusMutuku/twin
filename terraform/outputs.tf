output "api_gateway_url" {
  description = "URL of the API Gateway"
  value       = aws_apigatewayv2_api.main.api_endpoint
}

output "s3_frontend_bucket" {
  description = "Name of the S3 bucket for frontend"
  value       = aws_s3_bucket.frontend.id
}

output "s3_memory_bucket" {
  description = "Name of the S3 bucket for memory storage"
  value       = aws_s3_bucket.memory.id
}

output "lambda_function_name" {
  description = "Name of the Lambda function"
  value       = aws_lambda_function.api.function_name
}

# Frontend website URL using S3 website endpoint (HTTP)
output "frontend_url" {
  description = "S3 website endpoint URL for the frontend (http)"
  value       = "http://${aws_s3_bucket.frontend.website_endpoint}"
}

# If user set use_custom_domain true, this will stay empty because we removed domain automation.
output "custom_domain_url" {
  description = "Root URL of the production site (only set if use_custom_domain=true and you manage domain manually)"
  value       = var.use_custom_domain ? "http://${var.root_domain}" : ""
}

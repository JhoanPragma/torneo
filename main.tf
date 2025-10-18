##########################################################
# main.tf — Infraestructura completa para torneos (AWS)
##########################################################

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  required_version = ">= 1.5.0"

  backend "s3" {
    bucket         = "torneos-tfstate"                  
    key            = "infrastructure/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "terraform-locks"
  }
}

##########################################################
# Provider
##########################################################
provider "aws" {
  region = var.aws_region
}

##########################################################
# Bucket S3 — Para almacenamiento de códigos QR
##########################################################
resource "aws_s3_bucket" "qr_bucket" {
  bucket = "${var.s3_bucket_name_prefix}-${var.environment}"

  tags = {
    Name        = "${var.project_name}-qr-bucket"
    Environment = var.environment
  }
}

resource "aws_s3_bucket_public_access_block" "qr_bucket_block" {
  bucket                  = aws_s3_bucket.qr_bucket.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

##########################################################
# DynamoDB Table — Para guardar ventas
##########################################################
resource "aws_dynamodb_table" "ventas_table" {
  name         = "Ventas"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "venta_id"

  attribute {
    name = "venta_id"
    type = "S"
  }

  tags = {
    Name        = "${var.project_name}-ventas"
    Environment = var.environment
  }
}

##########################################################
# IAM Role y Policy para Lambda
##########################################################
resource "aws_iam_role" "lambda_exec_role" {
  name = "${var.project_name}-lambda-exec-role-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "lambda_policy" {
  name = "${var.project_name}-lambda-policy-${var.environment}"
  role = aws_iam_role.lambda_exec_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # Permisos de CloudWatch Logs
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      },
      # Permisos para DynamoDB y S3
      {
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:GetItem",
          "dynamodb:Scan",
          "s3:GetObject",
          "s3:PutObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_dynamodb_table.ventas_table.arn,
          "${aws_s3_bucket.qr_bucket.arn}/*",
          aws_s3_bucket.qr_bucket.arn
        ]
      }
    ]
  })
}

##########################################################
# Lambda Functions
##########################################################
locals {
  lambdas = {
    torneos        = "crear-torneo-lambda"
    ventas         = "ventas-lambda"
    qr_generator   = "qr-generator-lambda"
    notificaciones = "notificaciones-lambda"
  }
}

resource "aws_lambda_function" "lambda_functions" {
  for_each = local.lambdas

  function_name = "${each.value}-${var.environment}"
  handler       = "index.handler"
  runtime       = "nodejs18.x"
  role          = aws_iam_role.lambda_exec_role.arn
  filename      = "${path.module}/lambda_placeholder.zip"
  source_code_hash = filebase64sha256("${path.module}/lambda_placeholder.zip")

  environment {
    variables = {
      ENVIRONMENT = var.environment
      BUCKET_NAME = aws_s3_bucket.qr_bucket.bucket
      TABLE_NAME  = aws_dynamodb_table.ventas_table.name
    }
  }

  tags = {
    Name        = each.value
    Environment = var.environment
  }
}

##########################################################
# API Gateway HTTP
##########################################################
resource "aws_apigatewayv2_api" "api" {
  name          = "${var.project_name}-api"
  protocol_type = "HTTP"
}

# Integraciones con cada Lambda
resource "aws_apigatewayv2_integration" "lambda_integration" {
  for_each = aws_lambda_function.lambda_functions

  api_id                 = aws_apigatewayv2_api.api.id
  integration_type       = "AWS_PROXY"
  integration_uri        = each.value.invoke_arn
  payload_format_version = "2.0"
}

# Rutas (una por Lambda)
resource "aws_apigatewayv2_route" "lambda_route" {
  for_each = aws_lambda_function.lambda_functions

  api_id    = aws_apigatewayv2_api.api.id
  route_key = "POST /${each.key}"
  target    = "integrations/${aws_apigatewayv2_integration.lambda_integration[each.key].id}"
}

# Permisos para que API Gateway invoque las Lambdas
resource "aws_lambda_permission" "api_invoke" {
  for_each = aws_lambda_function.lambda_functions

  statement_id  = "AllowAPIGatewayInvoke-${each.key}"
  action        = "lambda:InvokeFunction"
  function_name = each.value.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.api.execution_arn}/*/*"
}

# Stage
resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.api.id
  name        = "$default"
  auto_deploy = true
}

##########################################################
# Outputs
##########################################################
output "api_gateway_url" {
  description = "Endpoint base del API Gateway"
  value       = aws_apigatewayv2_stage.default.invoke_url
}

output "lambda_endpoints" {
  description = "Rutas HTTP disponibles para probar en Postman"
  value = {
    torneos        = "${aws_apigatewayv2_stage.default.invoke_url}/torneos"
    ventas         = "${aws_apigatewayv2_stage.default.invoke_url}/ventas"
    qr_generator   = "${aws_apigatewayv2_stage.default.invoke_url}/qr_generator"
    notificaciones = "${aws_apigatewayv2_stage.default.invoke_url}/notificaciones"
  }
}

output "qr_bucket_name" {
  description = "Nombre del bucket donde se guardan los códigos QR"
  value       = aws_s3_bucket.qr_bucket.bucket
}

output "dynamodb_table_name" {
  description = "Nombre de la tabla DynamoDB creada"
  value       = aws_dynamodb_table.ventas_table.name
}

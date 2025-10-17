##########################################################
# main.tf — Infraestructura Serverless Torneos AWS
# CI/CD con GitHub Actions + Terraform (sin pasos manuales)
##########################################################

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

# --- Configuración del Proveedor ---
provider "aws" {
  region = var.aws_region
}

##########################################################
# 🪣 0. Bucket Backend Automático para Estado de Terraform
##########################################################
resource "aws_s3_bucket" "terraform_state_bucket" {
  bucket = "${var.project_name}-terraform-state-${random_id.state_suffix.hex}"
  force_destroy = true
  tags = {
    Name        = "terraform-state"
    Environment = var.environment
  }
}

resource "aws_s3_bucket_versioning" "terraform_state_versioning" {
  bucket = aws_s3_bucket.terraform_state_bucket.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_public_access_block" "terraform_state_block" {
  bucket                  = aws_s3_bucket.terraform_state_bucket.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# --- Generador de Sufijos Únicos ---
resource "random_id" "state_suffix" {
  byte_length = 4
}

resource "random_id" "bucket_suffix" {
  byte_length = 4
}

##########################################################
# ☁️ 1. Recursos de Integración (S3 y SNS)
##########################################################
resource "aws_s3_bucket" "qr_bucket" {
  bucket = "${var.s3_bucket_name_prefix}-${random_id.bucket_suffix.hex}" 
  force_destroy = true 
  tags = {
    Name        = "qr-codes"
    Environment = var.environment
  }
}

resource "aws_s3_bucket_ownership_controls" "qr_bucket_ownership_controls" {
  bucket = aws_s3_bucket.qr_bucket.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "qr_bucket_public_access_block" {
  bucket                  = aws_s3_bucket.qr_bucket.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
  depends_on              = [aws_s3_bucket_ownership_controls.qr_bucket_ownership_controls]
}

resource "aws_s3_object" "placeholder_zip" {
  bucket = aws_s3_bucket.qr_bucket.id
  key    = "placeholder.zip"
  source = "/dev/null"
  etag   = filemd5("/dev/null")
  depends_on = [aws_s3_bucket_public_access_block.qr_bucket_public_access_block]
}

resource "aws_sns_topic" "notifications_topic" {
  name = "tournament-notifications"
}

##########################################################
# 🔢 2. Tablas DynamoDB
##########################################################
resource "aws_dynamodb_table" "torneos_table" {
  name           = "Torneos"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "id"
  attribute {
    name = "id"
    type = "S"
  }
  tags = { Environment = var.environment }
}

resource "aws_dynamodb_table" "ventas_table" {
  name           = "Ventas"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "id"
  attribute {
    name = "id"
    type = "S"
  }
  tags = { Environment = var.environment }
}

resource "aws_dynamodb_table" "transmisiones_table" {
  name           = "Transmisiones"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "id"
  attribute {
    name = "id"
    type = "S"
  }
  tags = { Environment = var.environment }
}

##########################################################
# 🔐 3. IAM Roles & Policies
##########################################################
resource "aws_iam_role" "lambda_role" {
  name = "torneo_plataform_lambda_role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy" "lambda_policy" {
  name = "lambda_dynamodb_s3_sns_policy" 
  role = aws_iam_role.lambda_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid = "CloudWatchLogging"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
        ]
        Effect = "Allow"
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Sid = "DynamoDBAccess"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:GetItem"
        ]
        Effect = "Allow"
        Resource = [
          aws_dynamodb_table.torneos_table.arn,
          aws_dynamodb_table.ventas_table.arn,
          aws_dynamodb_table.transmisiones_table.arn
        ]
      },
      {
        Sid = "S3Access"
        Action = [
          "s3:PutObject",
          "s3:GetObject"
        ]
        Effect = "Allow"
        Resource = "${aws_s3_bucket.qr_bucket.arn}/*" 
      },
      {
        Sid = "SNSPublish"
        Action = "sns:Publish"
        Effect = "Allow"
        Resource = aws_sns_topic.notifications_topic.arn 
      }
    ]
  })
}

##########################################################
# ⚙️ 4. Funciones Lambda
##########################################################
locals {
  common_lambda_settings = {
    role      = aws_iam_role.lambda_role.arn
    handler   = "src/index.handler"
    runtime   = "nodejs18.x"
    s3_bucket = aws_s3_bucket.qr_bucket.id
    s3_key    = aws_s3_object.placeholder_zip.key
  }
}

resource "aws_lambda_function" "crear_torneo_lambda" {
  function_name = "crear-torneo-lambda"
  role          = local.common_lambda_settings.role
  handler       = local.common_lambda_settings.handler
  runtime       = local.common_lambda_settings.runtime
  s3_bucket     = local.common_lambda_settings.s3_bucket
  s3_key        = local.common_lambda_settings.s3_key

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.torneos_table.name
      ENV        = var.environment
    }
  }
}

resource "aws_lambda_function" "ventas_lambda" {
  function_name = "ventas-lambda"
  role          = local.common_lambda_settings.role
  handler       = local.common_lambda_settings.handler
  runtime       = local.common_lambda_settings.runtime
  s3_bucket     = local.common_lambda_settings.s3_bucket
  s3_key        = local.common_lambda_settings.s3_key

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.ventas_table.name
      ENV        = var.environment
    }
  }
}

resource "aws_lambda_function" "qr_generator_lambda" {
  function_name = "qr-generator-lambda"
  role          = local.common_lambda_settings.role
  handler       = local.common_lambda_settings.handler
  runtime       = local.common_lambda_settings.runtime
  s3_bucket     = local.common_lambda_settings.s3_bucket
  s3_key        = local.common_lambda_settings.s3_key

  environment {
    variables = {
      BUCKET_NAME = aws_s3_bucket.qr_bucket.id 
      TABLE_NAME  = aws_dynamodb_table.ventas_table.name
      ENV         = var.environment
    }
  }
}

resource "aws_lambda_function" "notificaciones_lambda" {
  function_name = "notificaciones-lambda"
  role          = local.common_lambda_settings.role
  handler       = local.common_lambda_settings.handler
  runtime       = local.common_lambda_settings.runtime
  s3_bucket     = local.common_lambda_settings.s3_bucket
  s3_key        = local.common_lambda_settings.s3_key

  environment {
    variables = {
      SNS_TOPIC_ARN          = aws_sns_topic.notifications_topic.arn 
      TRANSMISSION_TABLE_NAME = aws_dynamodb_table.transmisiones_table.name
      ENV                    = var.environment
    }
  }
}

##########################################################
# 🌐 5. API Gateway HTTP
##########################################################
resource "aws_apigatewayv2_api" "torneos_api" {
  name          = "TorneosAPI"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_integration" "torneos_integration" {
  api_id             = aws_apigatewayv2_api.torneos_api.id
  integration_type   = "AWS_PROXY"
  integration_uri    = aws_lambda_function.crear_torneo_lambda.arn
  integration_method = "POST"
}

resource "aws_apigatewayv2_route" "torneos_route" {
  api_id    = aws_apigatewayv2_api.torneos_api.id
  route_key = "POST /torneos"
  target    = "integrations/${aws_apigatewayv2_integration.torneos_integration.id}"
}

resource "aws_apigatewayv2_integration" "ventas_integration" {
  api_id             = aws_apigatewayv2_api.torneos_api.id
  integration_type   = "AWS_PROXY"
  integration_uri    = aws_lambda_function.ventas_lambda.arn
  integration_method = "POST"
}

resource "aws_apigatewayv2_route" "ventas_route" {
  api_id    = aws_apigatewayv2_api.torneos_api.id
  route_key = "POST /ventas"
  target    = "integrations/${aws_apigatewayv2_integration.ventas_integration.id}"
}

resource "aws_apigatewayv2_integration" "notificaciones_integration" {
  api_id             = aws_apigatewayv2_api.torneos_api.id
  integration_type   = "AWS_PROXY"
  integration_uri    = aws_lambda_function.notificaciones_lambda.arn
  integration_method = "POST"
}

resource "aws_apigatewayv2_route" "notificaciones_route" {
  api_id    = aws_apigatewayv2_api.torneos_api.id
  route_key = "POST /notificaciones"
  target    = "integrations/${aws_apigatewayv2_integration.notificaciones_integration.id}"
}

##########################################################
# 🔓 6. Permisos API → Lambda
##########################################################
resource "aws_lambda_permission" "torneos_permission" {
  statement_id  = "AllowAPIGatewayInvokeTorneos"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.crear_torneo_lambda.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.torneos_api.execution_arn}/*/*"
}

resource "aws_lambda_permission" "ventas_permission" {
  statement_id  = "AllowAPIGatewayInvokeVentas"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.ventas_lambda.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.torneos_api.execution_arn}/*/*"
}

resource "aws_lambda_permission" "notificaciones_permission" {
  statement_id  = "AllowAPIGatewayInvokeNotificaciones"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.notificaciones_lambda.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.torneos_api.execution_arn}/*/*"
}

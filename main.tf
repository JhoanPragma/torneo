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
# IAM Role y Policy para Lambdas
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
# Lambda Functions — Creación de las 4 funciones
##########################################################

# 1️⃣ Lambda de creación de torneos
resource "aws_lambda_function" "crear_torneo_lambda" {
  function_name = "crear-torneo-lambda"
  handler       = "index.handler"
  runtime       = "nodejs18.x"
  role          = aws_iam_role.lambda_exec_role.arn
  filename      = "${path.module}/lambda_placeholder.zip"
  source_code_hash = filebase64sha256("${path.module}/lambda_placeholder.zip")

  environment {
    variables = {
      ENVIRONMENT = var.environment
    }
  }

  tags = {
    Name        = "crear-torneo-lambda"
    Environment = var.environment
  }
}

# 2️⃣ Lambda de ventas
resource "aws_lambda_function" "ventas_lambda" {
  function_name = "ventas-lambda"
  handler       = "index.handler"
  runtime       = "nodejs18.x"
  role          = aws_iam_role.lambda_exec_role.arn
  filename      = "${path.module}/lambda_placeholder.zip"
  source_code_hash = filebase64sha256("${path.module}/lambda_placeholder.zip")

  environment {
    variables = {
      ENVIRONMENT = var.environment
      TABLE_NAME  = aws_dynamodb_table.ventas_table.name
    }
  }

  tags = {
    Name        = "ventas-lambda"
    Environment = var.environment
  }
}

# 3️⃣ Lambda de generación de QR
resource "aws_lambda_function" "qr_generator_lambda" {
  function_name = "qr-generator-lambda"
  handler       = "index.handler"
  runtime       = "nodejs18.x"
  role          = aws_iam_role.lambda_exec_role.arn
  filename      = "${path.module}/lambda_placeholder.zip"
  source_code_hash = filebase64sha256("${path.module}/lambda_placeholder.zip")

  environment {
    variables = {
      ENVIRONMENT = var.environment
      BUCKET_NAME = aws_s3_bucket.qr_bucket.bucket
    }
  }

  tags = {
    Name        = "qr-generator-lambda"
    Environment = var.environment
  }
}

# 4️⃣ Lambda de notificaciones
resource "aws_lambda_function" "notificaciones_lambda" {
  function_name = "notificaciones-lambda"
  handler       = "index.handler"
  runtime       = "nodejs18.x"
  role          = aws_iam_role.lambda_exec_role.arn
  filename      = "${path.module}/lambda_placeholder.zip"
  source_code_hash = filebase64sha256("${path.module}/lambda_placeholder.zip")

  environment {
    variables = {
      ENVIRONMENT = var.environment
    }
  }

  tags = {
    Name        = "notificaciones-lambda"
    Environment = var.environment
  }
}

##########################################################
# Outputs
##########################################################
output "qr_bucket_name" {
  description = "Nombre del bucket donde se guardan los códigos QR"
  value       = aws_s3_bucket.qr_bucket.bucket
}

output "dynamodb_table_name" {
  description = "Nombre de la tabla DynamoDB creada"
  value       = aws_dynamodb_table.ventas_table.name
}

output "lambda_names" {
  description = "Funciones Lambda creadas"
  value = [
    aws_lambda_function.crear_torneo_lambda.function_name,
    aws_lambda_function.ventas_lambda.function_name,
    aws_lambda_function.qr_generator_lambda.function_name,
    aws_lambda_function.notificaciones_lambda.function_name
  ]
}

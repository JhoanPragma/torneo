##########################################################
# main.tf — Infraestructura completa AWS Serverless
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

  required_version = ">= 1.6.0"
}

##########################################################
# Provider AWS
##########################################################

provider "aws" {
  region = var.aws_region
}

##########################################################
# Bucket para Terraform State (auto-creado y manejado)
##########################################################

resource "random_id" "state_suffix" {
  byte_length = 4
}

resource "aws_s3_bucket" "terraform_state_bucket" {
  bucket        = "${var.project_name}-tfstate-${random_id.state_suffix.hex}"
  force_destroy = true

  tags = {
    Name        = "${var.project_name}-tfstate"
    Environment = var.environment
  }
}

resource "aws_s3_bucket_ownership_controls" "tf_state" {
  bucket = aws_s3_bucket.terraform_state_bucket.id

  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

resource "aws_s3_bucket_public_access_block" "tf_state" {
  bucket                  = aws_s3_bucket.terraform_state_bucket.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "tf_state" {
  bucket = aws_s3_bucket.terraform_state_bucket.id

  versioning_configuration {
    status = "Enabled"
  }
}

##########################################################
# Backend remoto en el bucket de state
##########################################################

terraform {
  backend "s3" {
    bucket         = "torneos-tfstate" # se reemplaza automáticamente por el generado
    key            = "terraform/state.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "terraform-locks"
  }
}

##########################################################
# Bucket para QR Codes
##########################################################

resource "random_id" "qr_suffix" {
  byte_length = 4
}

resource "aws_s3_bucket" "qr_bucket" {
  bucket        = "${var.s3_bucket_name_prefix}-${random_id.qr_suffix.hex}"
  force_destroy = true

  tags = {
    Name        = "${var.project_name}-qr-bucket"
    Environment = var.environment
  }
}

resource "aws_s3_bucket_ownership_controls" "qr_bucket" {
  bucket = aws_s3_bucket.qr_bucket.id

  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

resource "aws_s3_bucket_public_access_block" "qr_bucket" {
  bucket                  = aws_s3_bucket.qr_bucket.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "qr_bucket" {
  bucket = aws_s3_bucket.qr_bucket.id

  versioning_configuration {
    status = "Enabled"
  }
}

##########################################################
# DynamoDB (para ventas y torneos)
##########################################################

resource "aws_dynamodb_table" "ventas_table" {
  name           = "Ventas"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "ventaId"

  attribute {
    name = "ventaId"
    type = "S"
  }

  tags = {
    Name        = "Ventas"
    Environment = var.environment
  }
}

resource "aws_dynamodb_table" "torneos_table" {
  name           = "Torneos"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "torneoId"

  attribute {
    name = "torneoId"
    type = "S"
  }

  tags = {
    Name        = "Torneos"
    Environment = var.environment
  }
}

##########################################################
# SNS Topic para notificaciones
##########################################################

resource "aws_sns_topic" "notificaciones_topic" {
  name = "${var.project_name}-notificaciones"
}

##########################################################
# Rol IAM para las Lambdas
##########################################################

resource "aws_iam_role" "lambda_role" {
  name = "torneo_plataform_lambda_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

##########################################################
# API Gateway HTTP
##########################################################

resource "aws_apigatewayv2_api" "torneos_api" {
  name          = "${var.project_name}-api"
  protocol_type = "HTTP"
}

##########################################################
# Lambda placeholders (código se sube en GitHub Actions)
##########################################################

resource "aws_lambda_function" "crear_torneo_lambda" {
  function_name = "crear-torneo-lambda"
  role          = aws_iam_role.lambda_role.arn
  runtime       = "nodejs18.x"
  handler       = "index.handler"

  filename = "placeholder.zip"
  source_code_hash = filebase64sha256("placeholder.zip")

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.torneos_table.name
    }
  }

  depends_on = [aws_iam_role.lambda_role]
}

resource "aws_lambda_function" "ventas_lambda" {
  function_name = "ventas-lambda"
  role          = aws_iam_role.lambda_role.arn
  runtime       = "nodejs18.x"
  handler       = "index.handler"

  filename = "placeholder.zip"
  source_code_hash = filebase64sha256("placeholder.zip")

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.ventas_table.name
    }
  }

  depends_on = [aws_iam_role.lambda_role]
}

resource "aws_lambda_function" "qr_generator_lambda" {
  function_name = "qr-generator-lambda"
  role          = aws_iam_role.lambda_role.arn
  runtime       = "nodejs18.x"
  handler       = "index.handler"

  filename = "placeholder.zip"
  source_code_hash = filebase64sha256("placeholder.zip")

  environment {
    variables = {
      BUCKET_NAME = aws_s3_bucket.qr_bucket.bucket
    }
  }

  depends_on = [aws_iam_role.lambda_role]
}

resource "aws_lambda_function" "notificaciones_lambda" {
  function_name = "notificaciones-lambda"
  role          = aws_iam_role.lambda_role.arn
  runtime       = "nodejs18.x"
  handler       = "index.handler"

  filename = "placeholder.zip"
  source_code_hash = filebase64sha256("placeholder.zip")

  environment {
    variables = {
      TOPIC_ARN = aws_sns_topic.notificaciones_topic.arn
    }
  }

  depends_on = [aws_iam_role.lambda_role]
}

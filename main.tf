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
# DynamoDB Tables — Basado en el análisis de las Lambdas
##########################################################

# Tabla para la Lambda 'torneos'
resource "aws_dynamodb_table" "torneos_table" {
  name         = "Torneos"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "id"

  attribute {
    name = "id"
    type = "S"
  }

  tags = {
    Name        = "${var.project_name}-torneos"
    Environment = var.environment
  }
}

# Tabla para las Lambdas 'ventas' y 'qr_generator'
resource "aws_dynamodb_table" "ventas_table" {
  name         = "Ventas"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "id"

  attribute {
    name = "id"
    type = "S"
  }

  tags = {
    Name        = "${var.project_name}-ventas"
    Environment = var.environment
  }
}

# Tabla para la Lambda 'notificaciones'
resource "aws_dynamodb_table" "transmisiones_table" {
  name         = "Transmisiones"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "id"

  attribute {
    name = "id"
    type = "S"
  }

  tags = {
    Name        = "${var.project_name}-transmisiones"
    Environment = var.environment
  }
}

# Tabla para almacenar perfiles de usuario y roles de aplicación
resource "aws_dynamodb_table" "user_profiles_table" {
  name         = "UserProfiles"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "id"

  attribute {
    name = "id"
    type = "S"
  }

  tags = {
    Name        = "${var.project_name}-user-profiles"
    Environment = var.environment
  }
}

# Tabla de Datos Maestros: Categorías de Torneos
resource "aws_dynamodb_table" "categorias_table" {
  name         = "Categorias"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "codigo" # Usando 'codigo' como Hash Key para catálogos

  attribute {
    name = "codigo"
    type = "S"
  }

  tags = {
    Name        = "${var.project_name}-categorias"
    Environment = var.environment
  }
}

# Tabla de Datos Maestros: Tipos de Videojuegos
resource "aws_dynamodb_table" "tipos_juego_table" {
  name         = "TiposJuego"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "codigo" # Usando 'codigo' como Hash Key para catálogos

  attribute {
    name = "codigo"
    type = "S"
  }

  tags = {
    Name        = "${var.project_name}-tipos-juego"
    Environment = var.environment
  }
}

# Tabla de Datos Maestros: Etapas de Venta (NUEVA: Para precios dinámicos)
resource "aws_dynamodb_table" "sales_stages_table" {
  name         = "EtapasVenta"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "torneoId" # PK para consultar las etapas de venta por torneo

  attribute {
    name = "torneoId"
    type = "S"
  }

  tags = {
    Name        = "${var.project_name}-sales-stages"
    Environment = var.environment
  }
}

##########################################################
# SNS Topic — Para la Lambda de notificaciones
##########################################################
resource "aws_sns_topic" "notifications_topic" {
  name = "${var.project_name}-notifications-topic-${var.environment}"
  tags = {
    Name        = "${var.project_name}-notifications"
    Environment = var.environment
  }
}

##########################################################
# AWS Cognito — Para autenticación de usuarios
##########################################################
resource "aws_cognito_user_pool" "torneos_user_pool" {
  name                = "${var.project_name}-user-pool-${var.environment}"
  username_attributes = ["email"]
  password_policy {
    minimum_length    = 8
    require_lowercase = true
    require_numbers   = true
    require_symbols   = true
    require_uppercase = true
  }
  schema {
    name                = "email"
    attribute_data_type = "String"
    mutable             = false
    required            = true
  }
  tags = {
    Name        = "${var.project_name}-user-pool"
    Environment = var.environment
  }
}

resource "aws_cognito_user_pool_client" "app_client" {
  name         = "${var.project_name}-app-client-${var.environment}"
  user_pool_id = aws_cognito_user_pool.torneos_user_pool.id

  generate_secret     = false
  explicit_auth_flows = ["ALLOW_USER_PASSWORD_AUTH", "ALLOW_REFRESH_TOKEN_AUTH"]
}

##########################################################
# IAM Role y Policy para Lambda (Actualizado)
##########################################################
resource "aws_iam_role" "lambda_exec_role" {
  name = "${var.project_name}-lambda-exec-role-${var.environment}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action    = "sts:AssumeRole",
      Effect    = "Allow",
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "lambda_policy" {
  name = "${var.project_name}-lambda-policy-${var.environment}"
  role = aws_iam_role.lambda_exec_role.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect   = "Allow",
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"],
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Effect = "Allow",
        # Incluye PutItem, GetItem, UpdateItem, Scan (necesarios para aforo y etapas de venta)
        Action = ["dynamodb:PutItem", "dynamodb:GetItem", "dynamodb:UpdateItem", "dynamodb:Scan"], 
        Resource = [
          aws_dynamodb_table.torneos_table.arn,
          aws_dynamodb_table.ventas_table.arn,
          aws_dynamodb_table.transmisiones_table.arn,
          aws_dynamodb_table.user_profiles_table.arn,
          aws_dynamodb_table.categorias_table.arn,
          aws_dynamodb_table.tipos_juego_table.arn,
          aws_dynamodb_table.sales_stages_table.arn # <-- PERMISO AÑADIDO
        ]
      },
      {
        Effect   = "Allow",
        Action   = ["s3:GetObject", "s3:PutObject", "s3:ListBucket"],
        Resource = ["${aws_s3_bucket.qr_bucket.arn}/*", aws_s3_bucket.qr_bucket.arn]
      },
      {
        Effect   = "Allow",
        Action   = "sns:Publish",
        Resource = aws_sns_topic.notifications_topic.arn
      },
      # Permisos para que las Lambdas de Auth hablen con Cognito
      {
        Effect = "Allow",
        Action = ["cognito-idp:SignUp", "cognito-idp:ConfirmSignUp", "cognito-idp:InitiateAuth", "cognito-idp:AdminConfirmSignUp"],
        Resource = aws_cognito_user_pool.torneos_user_pool.arn
      },
      # Permisos para enviar datos de trazabilidad a X-Ray
      {
        Effect = "Allow",
        Action = ["xray:PutTraceSegments"],
        Resource = ["*"]
      }
    ]
  })
}

##########################################################
# Lambda Functions (con variables de entorno corregidas)
##########################################################
locals {
  # Añadimos las nuevas lambdas de autenticación y la nueva de Sub-Admin
  lambdas = {
    torneos           = "crear-torneo-lambda"
    ventas            = "ventas-lambda"
    qr_generator      = "qr-generator-lambda"
    notificaciones    = "notificaciones-lambda"
    signup            = "auth-signup-lambda"
    confirm           = "auth-confirm-lambda"
    login             = "auth-login-lambda"
    sub_admin_updater = "sub-admin-updater-lambda"
    dashboard_query   = "dashboard-query-lambda"
  }
}

resource "aws_lambda_function" "lambda_functions" {
  for_each = local.lambdas

  function_name    = "${each.value}-${var.environment}"
  handler          = "src/index.handler"
  runtime          = "nodejs18.x"
  role             = aws_iam_role.lambda_exec_role.arn
  filename         = "${path.module}/lambda_placeholder.zip"
  source_code_hash = filebase64sha254("${path.module}/lambda_placeholder.zip")

  # HABILITACIÓN DE X-RAY TRACING
  tracing_config {
    mode = "Active"
  }

  environment {
    variables = {
      ENVIRONMENT             = var.environment
      BUCKET_NAME             = aws_s3_bucket.qr_bucket.bucket
      TABLE_NAME              = each.key == "torneos" ? aws_dynamodb_table.torneos_table.name : aws_dynamodb_table.ventas_table.name
      SNS_TOPIC_ARN           = aws_sns_topic.notifications_topic.arn
      TRANSMISSION_TABLE_NAME = aws_dynamodb_table.transmisiones_table.name
      COGNITO_CLIENT_ID       = aws_cognito_user_pool_client.app_client.id
      USER_PROFILES_TABLE     = aws_dynamodb_table.user_profiles_table.name
      CATEGORIAS_TABLE        = aws_dynamodb_table.categorias_table.name,
      TIPOS_JUEGO_TABLE       = aws_dynamodb_table.tipos_juego_table.name
      SALES_STAGES_TABLE      = aws_dynamodb_table.sales_stages_table.name # <-- VARIABLE AÑADIDA
    }
  }

  tags = {
    Name        = each.value
    Environment = var.environment
  }
}

##########################################################
# API Gateway con Integración de Cognito
##########################################################
resource "aws_apigatewayv2_api" "api" {
  name          = "${var.project_name}-api"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_authorizer" "cognito_authorizer" {
  api_id           = aws_apigatewayv2_api.api.id
  authorizer_type  = "JWT"
  identity_sources = ["$request.header.Authorization"]
  name             = "${var.project_name}-cognito-authorizer"

  jwt_configuration {
    audience = [aws_cognito_user_pool_client.app_client.id]
    issuer   = "https://${aws_cognito_user_pool.torneos_user_pool.endpoint}"
  }
}

resource "aws_apigatewayv2_integration" "lambda_integration" {
  for_each = aws_lambda_function.lambda_functions

  api_id                 = aws_apigatewayv2_api.api.id
  integration_type       = "AWS_PROXY"
  integration_uri        = each.value.invoke_arn
  payload_format_version = "2.0"
}

# Rutas PROTEGIDAS (requieren token)
resource "aws_apigatewayv2_route" "protected_routes" {
  for_each = toset(["torneos", "ventas", "qr_generator", "notificaciones", "sub_admin_updater", "dashboard_query"])

  api_id    = aws_apigatewayv2_api.api.id
  
  # Definición de rutas: POST para acciones, PUT para actualizaciones, GET para el dashboard
  route_key = each.key == "sub_admin_updater" ? "PUT /torneos/sub-admins" : (
    each.key == "dashboard_query" ? "GET /dashboard/torneos" : "POST /${each.key}"
  )
  target    = "integrations/${aws_apigatewayv2_integration.lambda_integration[each.key].id}"

  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito_authorizer.id
}

# Rutas PÚBLICAS para autenticación (NO requieren token)
resource "aws_apigatewayv2_route" "public_routes" {
  for_each = toset(["signup", "confirm", "login"])

  api_id    = aws_apigatewayv2_api.api.id
  route_key = "POST /${each.key}"
  target    = "integrations/${aws_apigatewayv2_integration.lambda_integration[each.key].id}"
}

resource "aws_lambda_permission" "api_invoke" {
  for_each = aws_lambda_function.lambda_functions

  statement_id  = "AllowAPIGatewayInvoke-${each.key}"
  action        = "lambda:InvokeFunction"
  function_name = each.value.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.api.execution_arn}/*/*"
}

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
  value       = merge(
    { for k, v in aws_apigatewayv2_route.protected_routes : k => "${aws_apigatewayv2_stage.default.invoke_url}/${replace(replace(v.route_key, "POST /", ""), "PUT /", "")}" },
    { for k, v in aws_apigatewayv2_route.public_routes : k => "${aws_apigatewayv2_stage.default.invoke_url}/${replace(v.route_key, "POST /", "")}" }
  )
}

output "qr_bucket_name" {
  description = "Nombre del bucket donde se guardan los códigos QR"
  value       = aws_s3_bucket.qr_bucket.bucket
}

output "dynamodb_table_names" {
  description = "Nombres de las tablas DynamoDB creadas"
  value = {
    torneos           = aws_dynamodb_table.torneos_table.name
    ventas            = aws_dynamodb_table.ventas_table.name
    transmisiones     = aws_dynamodb_table.transmisiones_table.name
    user_profiles     = aws_dynamodb_table.user_profiles_table.name
    categorias        = aws_dynamodb_table.categorias_table.name,
    tipos_juego       = aws_dynamodb_table.tipos_juego_table.name
    sales_stages      = aws_dynamodb_table.sales_stages_table.name # <-- OUTPUT AÑADIDO
  }
}

output "sns_topic_arn" {
  description = "ARN del SNS Topic de notificaciones"
  value       = aws_sns_topic.notifications_topic.arn
}

output "cognito_user_pool_id" {
  description = "ID del User Pool de Cognito"
  value       = aws_cognito_user_pool.torneos_user_pool.id
}

output "cognito_user_pool_client_id" {
  description = "ID del Cliente del User Pool de Cognito"
  value       = aws_cognito_user_pool_client.app_client.id
}
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

# --- Generador de Sufijo Único ---
resource "random_id" "bucket_suffix" {
  byte_length = 4
}

# --- 0. Recursos de Integración (S3 y SNS) ---
resource "aws_s3_bucket" "qr_bucket" {
  # Concatenación del prefijo de la variable y el sufijo aleatorio
  bucket = "${var.s3_bucket_name_prefix}-${random_id.bucket_suffix.hex}" 
  
  # CRÍTICO: Indica que el bucket usará el nuevo modelo de seguridad (ACLs deshabilitados).
  object_ownership = "BucketOwnerEnforced"
  
  force_destroy = true 
  tags = {
    Name = "qr-codes"
  }
}

# CRÍTICO: Este recurso establece el bloqueo de acceso público, requerido por defecto en AWS.
resource "aws_s3_bucket_public_access_block" "qr_bucket_public_access_block" {
  bucket                  = aws_s3_bucket.qr_bucket.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# OBJETO PLACEHOLDER: Un archivo ZIP vacío para satisfacer el requisito de código de Lambda
resource "aws_s3_object" "placeholder_zip" {
  bucket = aws_s3_bucket.qr_bucket.id
  key    = "placeholder.zip"
  source = "/dev/null"
  etag   = filemd5("/dev/null")
}

resource "aws_sns_topic" "notifications_topic" {
  name = "tournament-notifications"
}

# --- 1. Tablas de DynamoDB ---
resource "aws_dynamodb_table" "torneos_table" {
  name           = "Torneos"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "id"
  attribute {
    name = "id"
    type = "S"
  }
}

resource "aws_dynamodb_table" "ventas_table" {
  name           = "Ventas"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "id"
  attribute {
    name = "id"
    type = "S"
  }
}

resource "aws_dynamodb_table" "transmisiones_table" {
  name           = "Transmisiones"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "id"
  attribute {
    name = "id"
    type = "S"
  }
}

# --- 2. Roles y Políticas de IAM ---
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
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
        ]
        Effect = "Allow"
        Resource = "arn:aws:logs:*:*:*"
      },
      {
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
        Action = [
          "s3:PutObject",
          "s3:GetObject"
        ]
        Effect = "Allow"
        Resource = "${aws_s3_bucket.qr_bucket.arn}/*" 
      },
      {
        Action = "sns:Publish"
        Effect = "Allow"
        Resource = aws_sns_topic.notifications_topic.arn 
      }
    ]
  })
}

# --- 3. Funciones Lambda ---
resource "aws_lambda_function" "crear_torneo_lambda" {
  function_name = "crear-torneo-lambda"
  role          = aws_iam_role.lambda_role.arn
  handler       = "src/index.handler"
  runtime       = "nodejs18.x"
  
  s3_bucket     = aws_s3_bucket.qr_bucket.id
  s3_key        = aws_s3_object.placeholder_zip.key

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.torneos_table.name
    }
  }
}

resource "aws_lambda_function" "ventas_lambda" {
  function_name = "ventas-lambda"
  role          = aws_iam_role.lambda_role.arn
  handler       = "src/index.handler"
  runtime       = "nodejs18.x"
  
  s3_bucket     = aws_s3_bucket.qr_bucket.id
  s3_key        = aws_s3_object.placeholder_zip.key

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.ventas_table.name
    }
  }
}

resource "aws_lambda_function" "qr_generator_lambda" {
  function_name = "qr-generator-lambda"
  role          = aws_iam_role.lambda_role.arn
  handler       = "src/index.handler"
  runtime       = "nodejs18.x"
  
  s3_bucket     = aws_s3_bucket.qr_bucket.id
  s3_key        = aws_s3_object.placeholder_zip.key

  environment {
    variables = {
      BUCKET_NAME = aws_s3_bucket.qr_bucket.id 
      TABLE_NAME  = aws_dynamodb_table.ventas_table.name
    }
  }
}

resource "aws_lambda_function" "notificaciones_lambda" {
  function_name = "notificaciones-lambda"
  role          = aws_iam_role.lambda_role.arn
  handler       = "src/index.handler"
  runtime       = "nodejs18.x"
  
  s3_bucket     = aws_s3_bucket.qr_bucket.id
  s3_key        = aws_s3_object.placeholder_zip.key

  environment {
    variables = {
      SNS_TOPIC_ARN          = aws_sns_topic.notifications_topic.arn 
      TRANSMISSION_TABLE_NAME = aws_dynamodb_table.transmisiones_table.name
    }
  }
}

# --- 4. API Gateway ---
resource "aws_apigatewayv2_api" "torneos_api" {
  name          = "TorneosAPI"
  protocol_type = "HTTP"
}

# 4.1. Recurso y Método para crear torneos
resource "aws_apigatewayv2_route" "torneos_route" {
  api_id    = aws_apigatewayv2_api.torneos_api.id
  route_key = "POST /torneos"
  target    = "integrations/${aws_apigatewayv2_integration.torneos_integration.id}"
}

resource "aws_apigatewayv2_integration" "torneos_integration" {
  api_id           = aws_apigatewayv2_api.torneos_api.id
  integration_type = "AWS_PROXY"
  integration_uri  = aws_lambda_function.crear_torneo_lambda.arn
  integration_method = "POST"
}

# 4.2. Recurso y Método para ventas
resource "aws_apigatewayv2_route" "ventas_route" {
  api_id    = aws_apigatewayv2_api.torneos_api.id
  route_key = "POST /ventas"
  target    = "integrations/${aws_apigatewayv2_integration.ventas_integration.id}"
}

resource "aws_apigatewayv2_integration" "ventas_integration" {
  api_id           = aws_apigatewayv2_api.torneos_api.id
  integration_type = "AWS_PROXY"
  integration_uri  = aws_lambda_function.ventas_lambda.arn
  integration_method = "POST"
}

# 4.3. Recurso y Método para notificaciones
resource "aws_apigatewayv2_route" "notificaciones_route" {
  api_id    = aws_apigatewayv2_api.torneos_api.id
  route_key = "POST /notificaciones"
  target    = "integrations/${aws_apigatewayv2_integration.notificaciones_integration.id}"
}

resource "aws_apigatewayv2_integration" "notificaciones_integration" {
  api_id           = aws_apigatewayv2_api.torneos_api.id
  integration_type = "AWS_PROXY"
  integration_uri  = aws_lambda_function.notificaciones_lambda.arn
  integration_method = "POST"
}

# --- 5. Permisos de Invocación del API Gateway ---
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
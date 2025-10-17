##########################################################
# variables.tf — Variables globales para infraestructura
##########################################################

# --- Región AWS ---
variable "aws_region" {
  description = "Región AWS donde se desplegará la infraestructura"
  type        = string
  default     = "us-east-1"
}

# --- Prefijo de nombre del bucket QR ---
variable "s3_bucket_name_prefix" {
  description = "Prefijo base para el bucket donde se guardarán los QR y otros recursos"
  type        = string
  default     = "torneos-qr"
}

# --- Entorno de despliegue ---
variable "environment" {
  description = "Nombre del entorno (ej: dev, staging, prod)"
  type        = string
  default     = "dev"
}

# --- Variables auxiliares opcionales ---
variable "lambda_runtime" {
  description = "Runtime utilizado por las funciones Lambda"
  type        = string
  default     = "nodejs18.x"
}

variable "lambda_handler" {
  description = "Handler principal de las funciones Lambda"
  type        = string
  default     = "src/index.handler"
}

variable "tags" {
  description = "Tags comunes aplicados a todos los recursos"
  type        = map(string)
  default = {
    Project     = "TorneosServerless"
    Owner       = "GitHubActions"
    ManagedBy   = "Terraform"
  }
}

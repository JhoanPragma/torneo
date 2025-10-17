##########################################################
# variables.tf — Variables globales para infraestructura
##########################################################

# Región AWS
variable "aws_region" {
  description = "Región donde se desplegarán los recursos de AWS"
  type        = string
  default     = "us-east-1"
}

# Entorno (ej: dev, staging, prod)
variable "environment" {
  description = "Nombre del entorno"
  type        = string
  default     = "dev"
}

# Nombre base del proyecto (usado para el bucket de estado)
variable "project_name" {
  description = "Nombre del proyecto usado como prefijo en recursos"
  type        = string
  default     = "torneos"
}

# Prefijo del bucket S3 para los QR codes
variable "s3_bucket_name_prefix" {
  description = "Prefijo para el bucket donde se guardarán los códigos QR"
  type        = string
  default     = "torneos-qr-codes"
}

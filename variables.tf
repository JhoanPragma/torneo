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
  description = "Nombre del entorno (dev, staging, prod)"
  type        = string
  default     = "dev"
}

# Nombre base del proyecto (usado para prefijos de recursos)
variable "project_name" {
  description = "Nombre base del proyecto usado como prefijo en recursos"
  type        = string
  default     = "torneos"
}

# Prefijo del bucket S3 donde se guardarán los códigos QR
variable "s3_bucket_name_prefix" {
  description = "Prefijo para el bucket donde se guardarán los códigos QR"
  type        = string
  default     = "torneos-qr-codes"
}

# Nombre del bucket S3 que almacenará el estado remoto de Terraform
variable "terraform_state_bucket_name" {
  description = "Nombre del bucket S3 para guardar el estado remoto de Terraform"
  type        = string
  default     = "torneos-tfstate"
}

# Ruta (key) dentro del bucket donde se guardará el archivo de estado
variable "terraform_state_key" {
  description = "Ruta del archivo de estado dentro del bucket"
  type        = string
  default     = "infrastructure/terraform.tfstate"
}

# ARN del perfil o rol de AWS (opcional, útil si se ejecuta desde GitHub Actions o pipelines)
variable "aws_profile" {
  description = "Perfil de AWS CLI a usar (opcional)"
  type        = string
  default     = "default"
}

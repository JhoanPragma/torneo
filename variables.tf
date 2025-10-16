variable "aws_region" {
  description = "Región de AWS donde se desplegará la infraestructura."
  type        = string
  default     = "us-east-1"
}

variable "s3_bucket_name_prefix" {
  description = "Prefijo para el nombre del Bucket S3 (debe ser globalmente único)."
  type        = string
  default     = "tournament-qr-codes"
}
output "api_endpoint" {
  description = "URL base del API Gateway HTTP para la invocación de servicios."
  value       = aws_apigatewayv2_api.torneos_api.api_endpoint
}

output "sns_topic_arn" {
  description = "ARN del tópico de SNS para la configuración de notificaciones."
  value       = aws_sns_topic.notifications_topic.arn
}

output "s3_bucket_name" {
  description = "Nombre del Bucket S3 para el almacenamiento de códigos QR."
  value       = aws_s3_bucket.qr_bucket.id
}
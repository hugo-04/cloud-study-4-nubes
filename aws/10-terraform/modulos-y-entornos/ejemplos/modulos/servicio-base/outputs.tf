output "url_cola" {
  description = "URL de la cola principal"
  value       = aws_sqs_queue.principal.url
}

output "arn_cola" {
  description = "ARN de la cola principal"
  value       = aws_sqs_queue.principal.arn
}

output "arn_dlq" {
  description = "ARN de la cola de mensajes fallidos"
  value       = aws_sqs_queue.dlq.arn
}

output "arn_rol" {
  description = "ARN del rol de la tarea"
  value       = aws_iam_role.tarea.arn
}

output "grupo_logs" {
  description = "Nombre del grupo de logs"
  value       = aws_cloudwatch_log_group.app.name
}

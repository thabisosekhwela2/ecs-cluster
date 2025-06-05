output "cluster_name" {
  description = "Name of the ECS cluster"
  value       = aws_ecs_cluster.test-cluster.name
}

output "task_definition_arn" {
  description = "ARN of the task definition"
  value       = aws_ecs_task_definition.service.arn
}

output "service_name" {
  description = "Name of the ECS service"
  value       = aws_ecs_service.ecs_service.name
}

output "rds_endpoint" {
  description = "The connection endpoint for the RDS instance"
  value       = aws_db_instance.sql_server.endpoint
}

output "vpc_id" {
  description = "ID of the VPC"
  value       = data.aws_vpc.default.id
}

output "subnet_ids" {
  description = "IDs of the subnets"
  value       = data.aws_subnets.default.ids
}

output "security_group_id" {
  description = "ID of the security group"
  value       = aws_security_group.ecs_sg.id
} 
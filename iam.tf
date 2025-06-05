# Get current AWS account ID
data "aws_caller_identity" "current" {}

# Reference the existing ECS Task Execution Role
data "aws_iam_role" "ecs_task_execution_role" {
  name = "ecsTaskExecutionRole"
}

# Additional policy for CloudWatch Logs
resource "aws_iam_role_policy" "ecs_task_execution_cloudwatch" {
  name = "ecs-cloudwatch-logs"
  role = data.aws_iam_role.ecs_task_execution_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams"
        ]
        Resource = [
          "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:/ecs/*:*"
        ]
      }
    ]
  })
}

# Policy for accessing Dynatrace PaaS token
resource "aws_iam_role_policy" "ecs_task_execution_dynatrace" {
  name = "ecs-dynatrace-paas"
  role = data.aws_iam_role.ecs_task_execution_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Resource = [
          aws_secretsmanager_secret.dynatrace_paas_token.arn
        ]
      }
    ]
  })
}

# Policy for Network Interface Management
resource "aws_iam_role_policy" "ecs_task_execution_network" {
  name = "ecs-network-interface"
  role = data.aws_iam_role.ecs_task_execution_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:CreateNetworkInterface",
          "ec2:DeleteNetworkInterface",
          "ec2:DetachNetworkInterface",
          "ec2:ModifyNetworkInterfaceAttribute",
          "ec2:DescribeNetworkInterfaces",
          "ec2:AttachNetworkInterface",
          "ec2:UnassignPrivateIpAddresses",
          "ec2:AssignPrivateIpAddresses",
          "rds:*"
        ]
        Resource = "*"
      }
    ]
  })
}

# Additional policy for RDS network interface management
resource "aws_iam_role_policy" "rds_network_management" {
  name = "rds-network-management"
  role = data.aws_iam_role.ecs_task_execution_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:AuthorizeSecurityGroupIngress",
          "ec2:RevokeSecurityGroupIngress",
          "ec2:UpdateSecurityGroupRuleDescriptionsIngress",
          "ec2:AuthorizeSecurityGroupEgress",
          "ec2:RevokeSecurityGroupEgress",
          "ec2:UpdateSecurityGroupRuleDescriptionsEgress",
          "ec2:ModifyNetworkInterfaceAttribute",
          "ec2:DeleteNetworkInterface",
          "ec2:DetachNetworkInterface",
          "ec2:AttachNetworkInterface",
          "rds:ModifyDBInstance",
          "rds:DeleteDBInstance",
          "rds:StopDBInstance",
          "rds:StartDBInstance"
        ]
        Resource = "*"
      }
    ]
  })
} 
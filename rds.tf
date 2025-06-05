# Create the enhanced monitoring role
resource "aws_iam_role" "rds_enhanced_monitoring" {
  name = "rds-enhanced-monitoring-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "monitoring.rds.amazonaws.com"
        }
      }
    ]
  })

  tags = var.common_tags
}

# Attach the enhanced monitoring policy
resource "aws_iam_role_policy_attachment" "rds_enhanced_monitoring" {
  role       = aws_iam_role.rds_enhanced_monitoring.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

# RDS SQL Server Instance
resource "aws_db_instance" "sql_server" {
  identifier           = "monitoring-db"
  engine              = "sqlserver-ex"
  engine_version      = "15.00.4335.1.v1"
  instance_class      = "db.t3.micro"
  allocated_storage   = 20
  storage_type        = "gp2"
  username            = var.db_username
  password            = var.db_password
  skip_final_snapshot = true
  publicly_accessible = true

  vpc_security_group_ids = [aws_security_group.rds_sg.id]

  backup_retention_period = 7
  backup_window          = "03:00-04:00"
  maintenance_window     = "Mon:04:00-Mon:05:00"

  auto_minor_version_upgrade = true
  copy_tags_to_snapshot     = true

  performance_insights_enabled = true
  monitoring_interval         = 60
  monitoring_role_arn        = aws_iam_role.rds_enhanced_monitoring.arn

  tags = merge(
    var.common_tags,
    {
      Name = "monitoring-db"
    }
  )

  lifecycle {
    create_before_destroy = true
    # Add a precondition to ensure the security group exists
    precondition {
      condition     = length(var.db_password) >= 8
      error_message = "The database password must be at least 8 characters long."
    }
  }

  # Force dependency on security group to ensure proper ordering
  depends_on = [aws_security_group.rds_sg]
}

# Null resource to handle RDS cleanup
resource "null_resource" "rds_cleanup" {
  triggers = {
    rds_instance_id = aws_db_instance.sql_server.id
  }

  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      aws rds stop-db-instance --db-instance-identifier ${self.triggers.rds_instance_id} || true
      sleep 300  # Wait for 5 minutes to ensure the instance is stopped
    EOT
  }
} 
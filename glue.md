# AWS Glue Configuration Documentation

## Overview
This document outlines the configuration and setup of AWS Glue for connecting to an Aurora PostgreSQL database through RDS Proxy. The setup includes necessary IAM roles, permissions, VPC endpoints, and security configurations.

## Infrastructure Components

### 1. AWS Glue Crawler
- Name: `production-aurora-crawler`
- Schedule: Daily at midnight UTC
- Database Target: Aurora PostgreSQL via RDS Proxy
- JDBC Connection: Custom PostgreSQL driver (postgresql-42.6.0.jar)

### 2. VPC Configuration
- VPC Endpoints:
  - AWS Glue service endpoint
  - AWS KMS endpoint (for encryption)
  - AWS Secrets Manager endpoint
  - S3 Gateway endpoint
- Private subnets with NAT Gateway
- Security Groups for Glue and RDS Proxy communication

### 3. S3 Buckets
- JDBC Drivers bucket: `production-jdbc-drivers-{account_id}`
  - Stores PostgreSQL JDBC driver
  - Contains Glue-specific folders:
    - `_glue_job_crawler/*`
    - `_crawler/*`
- Glue Assets bucket: `production-glue-assets-{account_id}`

## IAM Configuration

### 1. Glue Crawler Role
Base role configuration:
```hcl
resource "aws_iam_role" "glue_crawler" {
  name = "${var.environment}-glue-crawler-role"
  assume_role_policy = {
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "glue.amazonaws.com"
      }
    }]
  }
}
```

### 2. Attached Managed Policies
- `AWSGlueServiceRole`
- `AWSGlueConsoleFullAccess`
- `AWSGlueServiceNotebookRole`

### 3. Custom IAM Policies

#### JDBC Connection Policy
```hcl
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::${jdbc_bucket}",
        "arn:aws:s3:::${jdbc_bucket}/*",
        "arn:aws:s3:::${jdbc_bucket}/_glue_job_crawler/*",
        "arn:aws:s3:::${jdbc_bucket}/_crawler/*",
        "arn:aws:s3:::aws-glue-jdbc-drivers",
        "arn:aws:s3:::aws-glue-jdbc-drivers/*"
      ]
    }
  ]
}
```

#### Glue Job Permissions
```hcl
{
  "Effect": "Allow",
  "Action": [
    "glue:CreateJob",
    "glue:DeleteJob",
    "glue:GetJob",
    "glue:GetJobRun",
    "glue:StartJobRun",
    "glue:*Connection*",
    "glue:*Security*",
    "glue:*Table*",
    "glue:*Partition*",
    "glue:*Database*"
  ],
  "Resource": ["*"]
}
```

#### IAM PassRole Permission
```hcl
{
  "Effect": "Allow",
  "Action": ["iam:PassRole"],
  "Resource": [aws_iam_role.glue_crawler.arn]
}
```

#### VPC Access Permissions
```hcl
{
  "Effect": "Allow",
  "Action": [
    "ec2:CreateNetworkInterface",
    "ec2:DeleteNetworkInterface",
    "ec2:DescribeNetworkInterfaces",
    "ec2:DescribeVpcEndpoints",
    "ec2:DescribeRouteTables",
    "ec2:DescribeSecurityGroups",
    "ec2:DescribeSubnets",
    "ec2:DescribeVpcAttribute"
  ],
  "Resource": ["*"]
}
```

## Security Configuration

### 1. Security Groups
- Glue Security Group:
  - Outbound: All traffic
  - Inbound: Self-referential
- RDS Proxy Security Group:
  - Inbound: PostgreSQL (5432) from Glue security group
  - Outbound: All traffic

### 2. Encryption and Secrets
- KMS encryption for Aurora cluster
- Secrets Manager for database credentials
- VPC endpoints for secure communication

## JDBC Connection Configuration

```hcl
resource "aws_glue_connection" "aurora" {
  name = "${var.environment}-aurora-connection"
  connection_type = "JDBC"

  physical_connection_requirements {
    availability_zone = data.aws_availability_zones.available.names[0]
    security_group_id_list = [aws_security_group.glue.id]
    subnet_id = aws_subnet.private[0].id
  }

  connection_properties = {
    JDBC_CONNECTION_URL = "jdbc:postgresql://${aws_db_proxy.aurora.endpoint}:5432/${var.database_name}"
    USERNAME = var.master_username
    PASSWORD = random_password.master_password.result
    JDBC_DRIVER_CLASS_NAME = "org.postgresql.Driver"
    JDBC_DRIVER_JAR_URI = "s3://${aws_s3_bucket.jdbc_drivers.id}/postgresql-42.6.0.jar"
    JDBC_ENFORCE_SSL = "false"
  }
}
```

## Troubleshooting

Common issues and solutions:
1. IAM Permissions: Ensure all required permissions are properly configured
2. VPC Endpoints: Verify endpoints are created and accessible
3. Security Groups: Check inbound/outbound rules
4. JDBC Driver: Confirm driver is uploaded to S3 and accessible
5. Network Access: Verify VPC and subnet configurations

## Maintenance

Regular maintenance tasks:
1. Monitor Glue crawler logs in CloudWatch
2. Review and update JDBC driver versions
3. Check for security group rule changes
4. Monitor VPC endpoint health
5. Review IAM role permissions periodically 
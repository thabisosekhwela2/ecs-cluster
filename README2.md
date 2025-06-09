# AWS Aurora PostgreSQL Infrastructure Setup

This repository contains the infrastructure code and documentation for setting up an Aurora PostgreSQL database in AWS using Terraform.

## Table of Contents
- [Prerequisites](#prerequisites)
- [Infrastructure Components](#infrastructure-components)
- [Installation Steps](#installation-steps)
- [Database Schema](#database-schema)
- [Access and Security](#access-and-security)
- [Troubleshooting](#troubleshooting)

## Prerequisites

### Required Tools
- AWS CLI
- Terraform
- Session Manager Plugin
- PostgreSQL Client

### Installation Commands

1. AWS CLI (macOS):
```bash
brew install awscli
aws configure  # Configure with your AWS credentials
```

2. Session Manager Plugin (macOS):
```bash
curl "https://s3.amazonaws.com/session-manager-downloads/plugin/latest/mac_arm64/session-manager-plugin.pkg" -o "session-manager-plugin.pkg"
sudo installer -pkg session-manager-plugin.pkg -target /
```

3. PostgreSQL Client (on Bastion Host):
```bash
sudo amazon-linux-extras enable postgresql14
sudo yum install -y postgresql
```

## Infrastructure Components

### Network Architecture
- VPC in af-south-1 (Cape Town)
- 3 Private Subnets
- 3 Public Subnets
- NAT Gateway
- Internet Gateway
- Route Tables

### Aurora PostgreSQL Configuration
- Engine: Aurora PostgreSQL 15.3
- Instance Type: db.t3.medium
- Serverless v2 Configuration:
  - Minimum ACU: 0.5
  - Maximum ACU: 1.0

### Security Components
- KMS Encryption
- AWS Secrets Manager
- Security Groups
- IAM Roles
- RDS Proxy
- Bastion Host

## Installation Steps

### 1. Clone and Initialize
```bash
git clone [repository-url]
cd [repository-name]
terraform init
```

### 2. Deploy Infrastructure
```bash
terraform plan
terraform apply
```

### 3. Connect to Bastion Host
```bash
aws ssm start-session --target i-01000a62e4a02beac
```

### 4. Database Access
Retrieve credentials from Secrets Manager:
```bash
aws secretsmanager get-secret-value \
  --secret-id production/aurora/credentials-[timestamp] \
  --region af-south-1 \
  --query 'SecretString' \
  --output text
```

Connect to database:
```bash
PGPASSWORD='your-password' psql \
  -h production-aurora-cluster.cluster-cu0bs0wptl6q.af-south-1.rds.amazonaws.com \
  -U dbadmin \
  -d myapp \
  -p 5432
```

## Database Schema

### Tables Structure

1. Users Table
```sql
CREATE TABLE IF NOT EXISTS users (
    id SERIAL PRIMARY KEY,
    username VARCHAR(50) UNIQUE NOT NULL,
    email VARCHAR(255) UNIQUE NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);
```

2. Products Table
```sql
CREATE TABLE IF NOT EXISTS products (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    description TEXT,
    price DECIMAL(10,2) NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);
```

3. Orders Table
```sql
CREATE TABLE IF NOT EXISTS orders (
    id SERIAL PRIMARY KEY,
    user_id INTEGER REFERENCES users(id),
    total_amount DECIMAL(10,2) NOT NULL,
    status VARCHAR(20) NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);
```

4. Order Items Table
```sql
CREATE TABLE IF NOT EXISTS order_items (
    id SERIAL PRIMARY KEY,
    order_id INTEGER REFERENCES orders(id),
    product_id INTEGER REFERENCES products(id),
    quantity INTEGER NOT NULL,
    unit_price DECIMAL(10,2) NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);
```

### Sample Data
The database is seeded with:
- 3 sample users
- 4 products
- 3 orders
- 4 order items

To seed the database, use the provided `seed.sql` file:
```bash
PGPASSWORD='your-password' psql \
  -h [aurora-endpoint] \
  -U dbadmin \
  -d myapp \
  -f seed.sql
```

## Access and Security

### Connection Endpoints
- Cluster Endpoint: `production-aurora-cluster.cluster-cu0bs0wptl6q.af-south-1.rds.amazonaws.com`
- Reader Endpoint: `production-aurora-cluster.cluster-ro-cu0bs0wptl6q.af-south-1.rds.amazonaws.com`
- Proxy Endpoint: `production-aurora-proxy.proxy-cu0bs0wptl6q.af-south-1.rds.amazonaws.com`

### Security Groups
1. Aurora Security Group
   - Inbound: PostgreSQL (5432) from Bastion and RDS Proxy
   - Outbound: All traffic

2. RDS Proxy Security Group
   - Inbound: PostgreSQL (5432) from private subnets
   - Outbound: All traffic

3. Bastion Security Group
   - Outbound: All traffic

### IAM Roles
1. Bastion Host Role
```hcl
resource "aws_iam_role" "bastion" {
  name = "${var.environment}-bastion-role"
  # Allows EC2 to assume this role
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
  })
}

# Policy for Secrets Manager access
resource "aws_iam_role_policy" "bastion_secrets" {
  name = "${var.environment}-bastion-secrets-policy"
  role = aws_iam_role.bastion.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = ["secretsmanager:GetSecretValue"]
        Resource = [aws_secretsmanager_secret.aurora_credentials.arn]
      },
      {
        Effect = "Allow"
        Action = ["kms:Decrypt"]
        Resource = [aws_kms_key.aurora.arn]
      }
    ]
  })
}
```

2. RDS Proxy Role
```hcl
resource "aws_iam_role" "rds_proxy" {
  name = "${var.environment}-rds-proxy-role"
  # Policy details in aurora.tf
}
```

## Troubleshooting

### Common Issues

1. Session Manager Connection Issues
```bash
# Check instance status
aws ec2 describe-instances \
  --instance-ids i-01000a62e4a02beac \
  --region af-south-1

# Verify IAM roles
aws iam get-role --role-name production-bastion-role
```

2. Database Connection Issues
```bash
# Test network connectivity
nc -zv [aurora-endpoint] 5432

# Check security group rules
aws ec2 describe-security-groups \
  --group-ids sg-0bd3f6cadc103d69a
```

3. Secrets Manager Access
```bash
# List available secrets
aws secretsmanager list-secrets --region af-south-1

# Test secret access
aws secretsmanager get-secret-value \
  --secret-id [secret-arn] \
  --region af-south-1
```

### Useful Commands

1. View Aurora Cluster Status
```bash
aws rds describe-db-clusters \
  --db-cluster-identifier production-aurora-cluster \
  --region af-south-1
```

2. Monitor CloudWatch Logs
```bash
aws logs get-log-events \
  --log-group-name /aws/rds/cluster/production-aurora-cluster \
  --log-stream-name [log-stream-name]
```

3. Database Maintenance
```sql
-- Check active connections
SELECT * FROM pg_stat_activity;

-- View table sizes
SELECT 
    relname as table_name,
    pg_size_pretty(pg_total_relation_size(relid)) as total_size
FROM pg_catalog.pg_statio_user_tables
ORDER BY pg_total_relation_size(relid) DESC;
```

## Cost Management

### Resource Optimization
- Serverless v2 scaling configuration (0.5-1.0 ACUs)
- t3.medium instance type selection
- Storage auto-scaling

### Monitoring
- CloudWatch metrics for resource utilization
- Cost Explorer tags for tracking
- Budget alerts configuration

## Maintenance and Backup

### Backup Configuration
- Automated backups enabled
- Retention period: 7 days
- Point-in-time recovery enabled

### Update Strategy
- Minor version updates automated
- Major version updates manual
- Maintenance window: [specify your maintenance window]

## Contributing

Please read [CONTRIBUTING.md](CONTRIBUTING.md) for details on our code of conduct and the process for submitting pull requests.

## License

This project is licensed under the MIT License - see the [LICENSE.md](LICENSE.md) file for details. 
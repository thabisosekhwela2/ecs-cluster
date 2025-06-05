# Compute Dynatrace API URL if not provided
locals {
  dynatrace_api_url = coalesce(var.dynatrace_api_url, "${var.dynatrace_tenant_url}/api")
}

# ECS Cluster
resource "aws_ecs_cluster" "test-cluster" {
  name = "monitoring-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = merge(
    var.common_tags,
    {
      Name = "monitoring-cluster"
    }
  )
}

resource "aws_ecs_cluster_capacity_providers" "fargate" {
  cluster_name = aws_ecs_cluster.test-cluster.name

  capacity_providers = ["FARGATE"]

  default_capacity_provider_strategy {
    base              = 1
    weight            = 5
    capacity_provider = "FARGATE"
  }
}

# Create DB password secret
resource "aws_secretsmanager_secret" "db_password" {
  name        = "db-password-new-${random_id.secret_suffix.hex}"
  description = "Database password for the RDS instance"
  tags        = var.common_tags
}

resource "aws_secretsmanager_secret_version" "db_password" {
  secret_id     = aws_secretsmanager_secret.db_password.id
  secret_string = var.db_password
}

# Add permissions for ECS task execution role to access secrets
resource "aws_iam_role_policy" "ecs_task_execution_secrets" {
  name = "ecs-secrets-access"
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
          aws_secretsmanager_secret.dynatrace_paas_token.arn,
          aws_secretsmanager_secret.db_password.arn
        ]
      }
    ]
  })
}

resource "aws_ecs_task_definition" "service" {
  family                   = "test-monitoring-3"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.ecs_task_cpu
  memory                   = var.ecs_task_memory
  execution_role_arn       = data.aws_iam_role.ecs_task_execution_role.arn
  task_role_arn            = aws_iam_role.fargate-assume-role.arn

  runtime_platform {
    cpu_architecture        = "ARM64"
    operating_system_family = "LINUX"
  }

  # Define ephemeral volume for Fargate
  volume {
    name = "oneagent"
  }

  container_definitions = jsonencode([
    {
      name      = "install-oneagent"
      image     = "alpine:3.19"
      cpu       = 128
      memory    = 256
      essential = false
      entryPoint = ["/bin/sh", "-c"]
      command    = [
        "set -e;",
        "ARCHIVE=$(mktemp);",
        "wget -O \"$ARCHIVE\" \"$DT_API_URL/v1/deployment/installer/agent/unix/paas-shared/latest?Api-Token=$DT_PAAS_TOKEN&flavor=default&include=dotnet&arch=arm&skip_install=true&output=liboneagentproc.so\";",
        "mkdir -p /opt/dynatrace/oneagent/agent/lib64;",
        "mv \"$ARCHIVE\" /opt/dynatrace/oneagent/agent/lib64/liboneagentproc.so;",
        "chmod a+r /opt/dynatrace/oneagent/agent/lib64/liboneagentproc.so;",
        "echo 'OneAgent library info:';",
        "file /opt/dynatrace/oneagent/agent/lib64/liboneagentproc.so;",
        "echo 'Library dependencies:';",
        "ldd /opt/dynatrace/oneagent/agent/lib64/liboneagentproc.so || true;"
      ]
      environment = [
        {
          name  = "DT_API_URL"
          value = local.dynatrace_api_url
        }
      ]
      secrets = [
        {
          name      = "DT_PAAS_TOKEN"
          valueFrom = aws_secretsmanager_secret.dynatrace_paas_token.arn
        }
      ]
      mountPoints = [
        {
          sourceVolume  = "oneagent"
          containerPath = "/opt/dynatrace/oneagent"
          readOnly     = false
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = "/ecs/oneagent-installer"
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "ecs"
          awslogs-create-group  = "true"
        }
      }
    },
    {
      name      = "profile-api"
      image     = var.app_image
      cpu       = 768
      memory    = 2816
      essential = true
      dependsOn = [
        {
          containerName = "install-oneagent"
          condition     = "COMPLETE"
        }
      ]
      environment = [
        {
          name  = "ASPNETCORE_ENVIRONMENT"
          value = var.environment
        },
        {
          name  = "DOTNET_RUNNING_IN_CONTAINER"
          value = "true"
        },
        {
          name  = "AWS_REGION"
          value = var.aws_region
        },
        {
          name  = "DB_HOST"
          value = var.db_host
        },
        {
          name  = "DB_PORT"
          value = tostring(1433)
        },
        {
          name  = "DB_NAME"
          value = "ProfileDb"
        },
        {
          name  = "DB_USER"
          value = var.db_username
        },
        # Minimal OneAgent configuration
        {
          name  = "LD_PRELOAD"
          value = "/opt/dynatrace/oneagent/agent/lib64/liboneagentproc.so"
        },
        {
          name  = "CORECLR_ENABLE_PROFILING"
          value = "1"
        },
        {
          name  = "CORECLR_PROFILER"
          value = "{846F5F1C-F9AE-4B07-969E-05C26BC060D8}"
        },
        {
          name  = "CORECLR_PROFILER_PATH"
          value = "/opt/dynatrace/oneagent/agent/lib64/liboneagentproc.so"
        },
        # Debugging settings
        {
          name  = "DT_DEBUG_MODE"
          value = "true"
        },
        {
          name  = "DT_LOGLEVELCON"
          value = "ALL"
        },
        {
          name  = "DT_LOGSTREAM"
          value = "stdout"
        }
      ]
      secrets = [
        {
          name      = "DB_PASS"
          valueFrom = aws_secretsmanager_secret.db_password.arn
        }
      ]
      portMappings = [
        {
          containerPort = 5062
          hostPort      = 5062
          protocol      = "tcp"
        }
      ]
      mountPoints = [
        {
          sourceVolume  = "oneagent"
          containerPath = "/opt/dynatrace/oneagent"
          readOnly     = true
        }
      ]
      healthCheck = {
        command     = [
          "CMD-SHELL", 
          "ls /opt/dynatrace/oneagent/agent/lib64/liboneagentproc.so && curl -f http://localhost:5062/health || exit 1"
        ]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 90
      }
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = "/ecs/dotnet"
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "ecs"
          awslogs-create-group  = "true"
        }
      }
    }
  ])
} 


# ECS Task Definition
/*resource "aws_ecs_task_definition" "service" {
  family                   = "test-monitoring-3"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.ecs_task_cpu
  memory                   = var.ecs_task_memory
  execution_role_arn       = data.aws_iam_role.ecs_task_execution_role.arn
  task_role_arn           = aws_iam_role.fargate-assume-role.arn

  runtime_platform {
    cpu_architecture        = "ARM64"
    operating_system_family = "LINUX"
  }

  # Define ephemeral volume for Fargate
  volume {
    name = "oneagent"
  }

  container_definitions = jsonencode([
    {
      name      = "install-oneagent"
      image     = "alpine:3.19"
      cpu       = tonumber("128")
      memory    = tonumber("256")
      essential = false
      entryPoint = ["/bin/sh", "-c"]
      command    = ["ARCHIVE=$(mktemp) && wget -O $ARCHIVE \"$DT_API_URL/v1/deployment/installer/agent/unix/paas/latest?Api-Token=$DT_PAAS_TOKEN&flavor=musl&include=all&arch=arm\" && unzip -o -d /opt/dynatrace/oneagent $ARCHIVE && rm -f $ARCHIVE && echo 'OneAgent files:' && ls -la /opt/dynatrace/oneagent && echo 'Agent lib files:' && ls -la /opt/dynatrace/oneagent/agent/lib64"]
      environment = [
        {
          name  = "DT_API_URL"
          value = local.dynatrace_api_url
        },
        {
          name  = "DT_DEBUG_MODE"
          value = "true"
        }
      ]
      secrets = [
        {
          name      = "DT_PAAS_TOKEN"
          valueFrom = aws_secretsmanager_secret.dynatrace_paas_token.arn
        }
      ]
      mountPoints = [
        {
          sourceVolume  = "oneagent"
          containerPath = "/opt/dynatrace/oneagent"
          readOnly     = false
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = "/ecs/oneagent-installer"
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "ecs"
          mode                  = "non-blocking"
          awslogs-create-group  = "true"
          max-buffer-size       = "25m"
        }
      }
    },
    {
      name      = "profile-api"
      image     = var.app_image
      cpu       = tonumber("768")
      memory    = tonumber("2816")
      essential = true
      dependsOn = [
        {
          containerName = "install-oneagent"
          condition    = "COMPLETE"
        }
      ]
      environment = [
        {
          name  = "ASPNETCORE_ENVIRONMENT"
          value = var.environment
        },
        {
          name  = "DOTNET_RUNNING_IN_CONTAINER"
          value = "true"
        },
        {
          name  = "AWS_REGION"
          value = var.aws_region
        },
        {
          name  = "DB_HOST"
          value = var.db_host
        },
        {
          name  = "DB_PORT"
          value = tostring(1433)
        },
        {
          name  = "DB_NAME"
          value = "ProfileDb"
        },
        {
          name  = "DB_USER"
          value = var.db_username
        },
        {
          name  = "DB_PASS"
          value = var.db_password
        },
        {
          name  = "LD_PRELOAD"
          value = "/opt/dynatrace/oneagent/agent/lib64/liboneagentproc.so"
        },
        {
          name  = "DT_ARMHF_ONEAGENT_LIBRARY_PATH"
          value = "/opt/dynatrace/oneagent/agent/lib64"
        },
        {
          name  = "CORECLR_ENABLE_PROFILING"
          value = "1"
        },
        {
          name  = "CORECLR_PROFILER"
          value = "{846F5F1C-F9AE-4B07-969E-05C26BC060D8}"
        },
        {
          name  = "CORECLR_PROFILER_PATH"
          value = "/opt/dynatrace/oneagent/agent/lib64/liboneagentproc.so"
        },
        {
          name  = "DT_CONTAINER_NAME"
          value = "profile-api"
        },
        {
          name  = "LD_LIBRARY_PATH"
          value = "/opt/dynatrace/oneagent/agent/lib64:/opt/dynatrace/oneagent/agent/lib64/system:/usr/lib"
        },
        {
          name  = "DT_CUSTOM_PROP"
          value = "Environment=${var.environment} Service=ProfileApi"
        },
        {
          name  = "DT_TAGS"
          value = "Environment=${var.environment} Service=ProfileApi"
        },
        {
          name  = "DT_APPLICATIONID"
          value = "ProfileApi"
        },
        {
          name  = "DT_PROCESSGROUP"
          value = "ProfileApi-ECS"
        },
        {
          name  = "DT_CLUSTER_ID"
          value = "monitoring-cluster"
        },
        {
          name  = "DT_NETWORK_ZONE"
          value = "default"
        },
        {
          name  = "DT_MONITORING_ENABLED"
          value = "true"
        },
        {
          name  = "DT_TENANT"
          value = replace(var.dynatrace_tenant_url, "https://", "")
        },
        {
          name  = "DT_CONNECTION_POINT"
          value = replace(var.dynatrace_tenant_url, "https://", "")
        },
        {
          name  = "DT_METRICS_INGEST"
          value = "1"
        },
        {
          name  = "DT_LOGSTREAM"
          value = "stdout"
        },
        {
          name  = "DT_LOGLEVELCON"
          value = "INFO"
        },
        {
          name  = "DT_LOGMONITORING"
          value = "1"
        },
        {
          name  = "DT_LOG_INGEST"
          value = "1"
        }
      ]
      portMappings = [
        {
          name          = "profile-api-5062-tcp"
          containerPort = 5062
          hostPort      = 5062
          protocol      = "tcp"
          appProtocol   = "http"
        }
      ]
      mountPoints = [
        {
          sourceVolume  = "oneagent"
          containerPath = "/opt/dynatrace/oneagent"
          readOnly     = true
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = "/ecs/dotnet"
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "ecs"
          mode                  = "non-blocking"
          awslogs-create-group  = "true"
          max-buffer-size       = "25m"
        }
      }
    }
  ])
} 
*/
# ECS Service
resource "aws_ecs_service" "ecs_service" {
  name            = "monitoring-service"
  cluster         = aws_ecs_cluster.test-cluster.id
  task_definition = aws_ecs_task_definition.service.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = data.aws_subnets.default.ids
    security_groups  = [aws_security_group.ecs_sg.id]
    assign_public_ip = true
  }
} 
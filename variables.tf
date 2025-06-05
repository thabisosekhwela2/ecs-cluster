variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "af-south-1"

  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-\\d{1}$", var.aws_region))
    error_message = "The aws_region value must be a valid AWS region name (e.g., us-west-1, eu-central-1)."
  }
}

variable "environment" {
  description = "Environment name (e.g., Development, Staging, Production)"
  type        = string
  default     = "Development"

  validation {
    condition     = contains(["Development", "Staging", "Production"], var.environment)
    error_message = "Environment must be one of: Development, Staging, Production."
  }
}

variable "db_username" {
  description = "Database administrator username. Must be 1-16 characters long and contain only alphanumeric characters."
  type        = string
  default     = "admin"

  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9]{0,15}$", var.db_username))
    error_message = "The db_username must be 1-16 characters long, start with a letter, and contain only alphanumeric characters."
  }
}

variable "db_password" {
  description = "Database administrator password. Must be at least 8 characters long and contain at least one uppercase letter, one lowercase letter, one number, and one special character."
  type        = string
  sensitive   = true

  validation {
    condition     = alltrue([
      length(var.db_password) >= 8,
      can(regex("[A-Z]", var.db_password)),
      can(regex("[a-z]", var.db_password)),
      can(regex("[0-9]", var.db_password)),
      can(regex("[@$!%*?&]", var.db_password))
    ])
    error_message = "The db_password must be at least 8 characters long and contain at least one uppercase letter, one lowercase letter, one number, and one special character (@$!%*?&)."
  }
}

variable "ecs_task_cpu" {
  description = "CPU units for the ECS task (1024 = 1 vCPU). Valid values: 256, 512, 1024, 2048, 4096"
  type        = string
  default     = "1024"

  validation {
    condition     = can(regex("^(256|512|1024|2048|4096)$", var.ecs_task_cpu))
    error_message = "The ecs_task_cpu value must be one of: 256, 512, 1024, 2048, 4096."
  }
}

variable "ecs_task_memory" {
  description = "Memory (in MiB) for the ECS task. Must be appropriate for the CPU units selected."
  type        = string
  default     = "3072"

  validation {
    condition     = can(tonumber(var.ecs_task_memory)) && tonumber(var.ecs_task_memory) >= 512 && tonumber(var.ecs_task_memory) <= 30720
    error_message = "The ecs_task_memory value must be between 512 and 30720 MiB."
  }
}

variable "dynatrace_tenant_url" {
  description = "Dynatrace tenant URL (e.g., https://{your-environment-id}.live.dynatrace.com)"
  type        = string

  validation {
    condition     = can(regex("^https://[a-zA-Z0-9-]+\\.live\\.dynatrace\\.com$|^https://[a-zA-Z0-9.-]+/e/[a-zA-Z0-9-]+$", var.dynatrace_tenant_url))
    error_message = "The dynatrace_tenant_url must be a valid Dynatrace tenant URL (SaaS or Managed)."
  }
}

variable "dynatrace_api_url" {
  description = "Dynatrace API URL. For SaaS: https://{your-environment-id}.live.dynatrace.com/api, For Managed: https://{cluster}/e/{your-environment-id}/api, For ActiveGate: https://{your-active-gate-IP-or-hostname}:9999/e/{your-environment-id}/api"
  type        = string
  default     = null

  validation {
    condition     = var.dynatrace_api_url == null || can(regex("^https://.*", var.dynatrace_api_url))
    error_message = "The dynatrace_api_url must be a valid HTTPS URL or null."
  }
}

variable "dynatrace_oneagent_flavor" {
  description = "OneAgent flavor to use. Valid options are 'default' or 'musl' (for Alpine images)"
  type        = string
  default     = "default"

  validation {
    condition     = contains(["default", "musl"], var.dynatrace_oneagent_flavor)
    error_message = "OneAgent flavor must be either 'default' or 'musl'."
  }
}

variable "dynatrace_tenant_token" {
  description = "Dynatrace PaaS token with required permissions: InstallerDownload, DataExport, DTAQLAccess, ReadConfig, WriteConfig"
  type        = string
  sensitive   = true

  validation {
    condition     = can(regex("^dt0c01\\.[A-Z0-9]+\\.[A-Z0-9]+$", var.dynatrace_tenant_token))
    error_message = "The dynatrace_tenant_token must be a valid Dynatrace token format starting with 'dt0c01.' followed by two sections of uppercase letters and numbers separated by a period."
  }
}

variable "app_image" {
  description = "The ECR image to use for the application. Must be a valid ECR image URL."
  type        = string
  default     = "644496295335.dkr.ecr.af-south-1.amazonaws.com/profile-api:latest"

  validation {
    condition     = can(regex("^\\d+\\.dkr\\.ecr\\.[a-z0-9-]+\\.amazonaws\\.com/[a-z0-9-]+:[a-zA-Z0-9._-]+$", var.app_image))
    error_message = "The app_image must be a valid ECR image URL."
  }
}

variable "db_host" {
  description = "Database host endpoint"
  type        = string
  default     = ""

  validation {
    condition     = can(regex("^[a-zA-Z0-9.-]*$", var.db_host))
    error_message = "The db_host must be a valid hostname containing only letters, numbers, dots, and hyphens."
  }
}

variable "common_tags" {
  description = "Common tags to be applied to all resources"
  type        = map(string)
  default = {
    Environment = "Development"
    Project     = "ECS-Dynatrace"
    ManagedBy   = "Terraform"
  }
} 
# Create a random suffix for the secret name
resource "random_id" "secret_suffix" {
  byte_length = 4
}

# Dynatrace PaaS token secret
resource "aws_secretsmanager_secret" "dynatrace_paas_token" {
  name                    = "dynatrace-paas-token-${random_id.secret_suffix.hex}"
  recovery_window_in_days = 0  # Immediate deletion
  force_overwrite_replica_secret = true

  tags = var.common_tags
}

# Store the secret value
resource "aws_secretsmanager_secret_version" "dynatrace_paas_token" {
  secret_id     = aws_secretsmanager_secret.dynatrace_paas_token.id
  secret_string = ""  # Using the token that worked in our test
} 
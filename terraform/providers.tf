provider "aws" {
  region = var.aws_region

  # Credentials come from the standard AWS chain (env vars, SSO profile,
  # instance role). Nothing is configured or stored here.

  default_tags {
    tags = merge(
      {
        Project     = "SecureVPC"
        Environment = var.environment
        ManagedBy   = "Terraform"
        Repository  = "github.com/Mighiana/SecureVPC"
      },
      var.extra_tags,
    )
  }
}

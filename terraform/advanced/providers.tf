provider "aws" {
  region = var.aws_region

  # Credentials come from the standard AWS chain (env vars, SSO profile,
  # instance role). Nothing is configured or stored here.

  default_tags {
    # Fixed tags come last so extra_tags cannot override the inventory tags
    # that cost-check.sh relies on.
    tags = merge(
      var.extra_tags,
      {
        Project     = "SecureVPC"
        Profile     = "advanced"
        Environment = var.environment
        ManagedBy   = "Terraform"
        Repository  = "github.com/Mighiana/SecureVPC"
      },
    )
  }
}

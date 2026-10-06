variable "name" {
  description = "Name prefix applied to every endpoint."
  type        = string
}

variable "vpc_id" {
  description = "VPC to create the endpoints in."
  type        = string
}

variable "region" {
  description = "AWS region."
  type        = string
}

variable "partition" {
  description = "AWS partition."
  type        = string
}

variable "account_id" {
  description = "AWS account ID; endpoint policies only allow principals and buckets from this account."
  type        = string
}

variable "subnet_ids" {
  description = "Endpoint-tier subnet IDs (one interface endpoint ENI per AZ)."
  type        = list(string)
}

variable "security_group_id" {
  description = "Security group attached to the interface endpoints."
  type        = string
}

variable "gateway_route_table_ids" {
  description = "Route tables that get the S3 gateway endpoint route."
  type        = list(string)
}

variable "interface_services" {
  description = "Interface endpoint service suffixes (com.amazonaws.<region>.<suffix>)."
  type        = list(string)
}

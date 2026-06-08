variable "environment" {
  description = "Fallback environment name if not using workspaces"
  type        = string
  default     = "dev"
}

variable "region" {
  description = "AWS Region"
  type        = string
  default     = "eu-central-1"
}

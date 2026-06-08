locals {
  workspace = terraform.workspace == "default" ? var.environment : terraform.workspace
}

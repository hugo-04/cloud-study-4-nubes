terraform {
  required_version = ">= 1.10"

  # Los valores concretos llegan con: terraform init -backend-config=backend.hcl
  backend "s3" {}
}

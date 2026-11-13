# The Floci provider gate (the contract every Phoenix root will adopt): the same
# config targets real AWS or local Floci, switched by var.floci.
provider "aws" {
  region = var.aws_region

  access_key                  = var.floci ? "test" : null
  secret_key                  = var.floci ? "test" : null
  skip_credentials_validation = var.floci
  skip_requesting_account_id  = var.floci
  skip_metadata_api_check     = var.floci
  s3_use_path_style           = var.floci

  dynamic "endpoints" {
    for_each = var.floci ? [1] : []
    content {
      organizations  = var.floci_endpoint
      controltower   = var.floci_endpoint
      servicecatalog = var.floci_endpoint
      iam            = var.floci_endpoint
      sts            = var.floci_endpoint
      dynamodb       = var.floci_endpoint
      s3             = var.floci_endpoint
      cloudformation = var.floci_endpoint
    }
  }
}

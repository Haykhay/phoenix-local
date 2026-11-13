variable "floci" {
  description = "Target a local Floci (endpoints + skip flags) instead of real AWS."
  type        = bool
  default     = true
}

variable "floci_endpoint" {
  type    = string
  default = "http://localhost:4566"
}

variable "aws_region" {
  type    = string
  default = "eu-west-1"
}

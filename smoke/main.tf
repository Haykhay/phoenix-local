# Smoke test for the Floci standard: stand up the three resources that decide
# whether Floci can really run Phoenix Layer 0 — Organizations, a Control Tower
# landing zone (the hard one), and a DynamoDB table (the registry shape).
# Applied against Floci in CI; proves the emulator + the provider gate work
# before wiring the full phoenix-aws-org roots.

resource "aws_organizations_organization" "this" {
  feature_set = "ALL"
}

resource "aws_controltower_landing_zone" "this" {
  version = "3.3"

  manifest_json = jsonencode({
    governedRegions = [var.aws_region]
    organizationStructure = {
      security = { name = "Security" }
      sandbox  = { name = "Sandbox" }
    }
    centralizedLogging = {
      accountId = "111111111111"
      configurations = {
        loggingBucket       = { retentionDays = 365 }
        accessLoggingBucket = { retentionDays = 3650 }
      }
      enabled = true
    }
    securityRoles    = { accountId = "222222222222" }
    accessManagement = { enabled = true }
  })
}

resource "aws_dynamodb_table" "registry" {
  name         = "phoenix-smoke-registry"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "group"

  attribute {
    name = "group"
    type = "S"
  }
}

output "org_id" {
  value = aws_organizations_organization.this.id
}

output "landing_zone_arn" {
  value = aws_controltower_landing_zone.this.arn
}

output "registry_table" {
  value = aws_dynamodb_table.registry.name
}

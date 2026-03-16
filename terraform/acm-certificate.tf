#
# ACM Certificate with DNS Validation
# Requests certificate and creates Route53 validation records automatically
#

# Request ACM certificate
resource "aws_acm_certificate" "openclaw" {
  domain_name       = var.domain_name
  validation_method = "DNS"

  tags = {
    Name      = "openclaw-teams-cert"
    Domain    = var.domain_name
    ManagedBy = "Terraform"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Data source: Find Route53 hosted zone
data "aws_route53_zone" "domain" {
  count        = var.domain_name != "" ? 1 : 0
  name         = var.route53_zone_name
  private_zone = false
}

# Create DNS validation records in Route53
resource "aws_route53_record" "cert_validation" {
  for_each = var.domain_name != "" ? {
    for dvo in aws_acm_certificate.openclaw.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  } : {}

  zone_id         = data.aws_route53_zone.domain[0].zone_id
  name            = each.value.name
  type            = each.value.type
  records         = [each.value.record]
  ttl             = 60
  allow_overwrite = true
}

# Wait for certificate validation to complete
resource "aws_acm_certificate_validation" "openclaw" {
  count                   = var.domain_name != "" ? 1 : 0
  certificate_arn         = aws_acm_certificate.openclaw.arn
  validation_record_fqdns = [for record in aws_route53_record.cert_validation : record.fqdn]

  timeouts {
    create = "30m"
  }
}

# Output certificate ARN
output "acm_certificate_arn" {
  description = "ARN of validated ACM certificate"
  value       = aws_acm_certificate.openclaw.arn
}

output "acm_certificate_status" {
  description = "Certificate validation status"
  value       = aws_acm_certificate.openclaw.status
}

output "acm_certificate_domain" {
  description = "Certificate domain name"
  value       = aws_acm_certificate.openclaw.domain_name
}

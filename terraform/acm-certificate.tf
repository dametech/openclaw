#
# Wildcard ACM certificate with Route53 DNS validation.
#

resource "aws_acm_certificate" "wildcard" {
  domain_name       = var.wildcard_domain_name
  validation_method = "DNS"

  tags = {
    Name      = "openclaw-wildcard-cert"
    Domain    = "openclaw.dametech.net"
    ManagedBy = "Terraform"
  }

  lifecycle {
    create_before_destroy = true
  }
}

data "aws_route53_zone" "domain" {
  name         = var.route53_zone_name
  private_zone = false
}

resource "aws_route53_record" "cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.wildcard.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  zone_id         = data.aws_route53_zone.domain.zone_id
  name            = each.value.name
  type            = each.value.type
  records         = [each.value.record]
  ttl             = 60
  allow_overwrite = true
}

resource "aws_acm_certificate_validation" "wildcard" {
  certificate_arn         = aws_acm_certificate.wildcard.arn
  validation_record_fqdns = [for record in aws_route53_record.cert_validation : record.fqdn]

  timeouts {
    create = "30m"
  }
}

output "acm_certificate_arn" {
  description = "ARN of the wildcard ACM certificate"
  value       = aws_acm_certificate.wildcard.arn
}

output "acm_certificate_status" {
  description = "Validation status of the wildcard ACM certificate"
  value       = aws_acm_certificate.wildcard.status
}

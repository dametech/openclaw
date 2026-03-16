#
# Route53 DNS Configuration
# Creates A record pointing to ALB
#

# Data source for Route53 zone (defined in acm-certificate.tf)

# Route53 A record for OpenClaw domain
resource "aws_route53_record" "openclaw" {
  count   = var.domain_name != "" ? 1 : 0
  zone_id = data.aws_route53_zone.domain[0].zone_id
  name    = var.domain_name
  type    = "A"

  alias {
    name                   = aws_lb.openclaw.dns_name
    zone_id                = aws_lb.openclaw.zone_id
    evaluate_target_health = true
  }
}

output "custom_domain_url" {
  description = "Custom domain webhook URL"
  value       = var.domain_name != "" ? "https://${var.domain_name}${var.teams_webhook_path}" : "Not configured"
}

#
# Optional Route53 DNS Configuration
# Creates A record pointing to ALB if domain_name is configured
#

# Route53 A record for custom domain
resource "aws_route53_record" "openclaw" {
  count   = var.create_route53_record ? 1 : 0
  zone_id = var.route53_zone_id
  name    = var.domain_name
  type    = "A"

  alias {
    name                   = aws_lb.openclaw.dns_name
    zone_id                = aws_lb.openclaw.zone_id
    evaluate_target_health = true
  }
}

output "custom_domain_url" {
  description = "Custom domain webhook URL (if configured)"
  value       = var.create_route53_record ? "https://${var.domain_name}${var.teams_webhook_path}" : "Not configured"
}

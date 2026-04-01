#
# Wildcard Route53 alias pointing subdomains at the existing shared ALB.
#

resource "aws_route53_record" "wildcard" {
  zone_id = data.aws_route53_zone.domain.zone_id
  name    = var.wildcard_domain_name
  type    = "A"

  alias {
    name                   = data.aws_lb.existing.dns_name
    zone_id                = data.aws_lb.existing.zone_id
    evaluate_target_health = true
  }
}

output "wildcard_domain_name" {
  description = "Wildcard DNS name routed to the shared ALB"
  value       = var.wildcard_domain_name
}

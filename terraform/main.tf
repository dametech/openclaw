#
# Shared OpenClaw edge infrastructure for Teams-enabled releases.
# Reuses the existing ALB and HTTPS listener.
#

data "aws_lb" "existing" {
  name = var.existing_alb_name
}

data "aws_lb_listener" "https" {
  load_balancer_arn = data.aws_lb.existing.arn
  port              = var.existing_https_listener_port
}

resource "aws_lb_listener_certificate" "wildcard" {
  listener_arn    = data.aws_lb_listener.https.arn
  certificate_arn = aws_acm_certificate.wildcard.arn

  depends_on = [aws_acm_certificate_validation.wildcard]
}

output "alb_dns_name" {
  description = "DNS name of the existing shared ALB"
  value       = data.aws_lb.existing.dns_name
}

output "alb_arn" {
  description = "ARN of the existing shared ALB"
  value       = data.aws_lb.existing.arn
}

output "alb_zone_id" {
  description = "Route53 zone ID of the existing shared ALB"
  value       = data.aws_lb.existing.zone_id
}

output "https_listener_arn" {
  description = "ARN of the existing HTTPS listener"
  value       = data.aws_lb_listener.https.arn
}

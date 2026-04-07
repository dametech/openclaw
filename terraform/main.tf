#
# Shared OpenClaw edge infrastructure for Teams-enabled releases.
# Reuses the existing ALB and HTTPS listener.
#

data "aws_lb" "existing" {
  name = var.existing_alb_name
}

resource "aws_lb_target_group" "ingress_nginx" {
  name_prefix = "ocing-"
  port        = 80
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = data.aws_lb.existing.vpc_id

  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
    path                = "/"
    protocol            = "HTTP"
    port                = "traffic-port"
    matcher             = "200-499"
  }

  lifecycle {
    create_before_destroy = true
  }
}

data "aws_lb_listener" "https" {
  load_balancer_arn = data.aws_lb.existing.arn
  port              = var.existing_https_listener_port
}

resource "aws_lb_target_group_attachment" "ingress_targets" {
  count             = length(var.ingress_target_ips)
  target_group_arn  = aws_lb_target_group.ingress_nginx.arn
  target_id         = var.ingress_target_ips[count.index]
  port              = 80
  availability_zone = "all"
}

resource "aws_lb_listener_certificate" "wildcard" {
  listener_arn    = data.aws_lb_listener.https.arn
  certificate_arn = aws_acm_certificate.wildcard.arn

  depends_on = [aws_acm_certificate_validation.wildcard]
}

resource "aws_lb_listener_rule" "wildcard_hosts" {
  listener_arn = data.aws_lb_listener.https.arn
  priority     = 100

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.ingress_nginx.arn
  }

  condition {
    host_header {
      values = [var.wildcard_domain_name]
    }
  }
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

output "ingress_target_group_arn" {
  description = "ARN of the shared ingress-nginx target group"
  value       = aws_lb_target_group.ingress_nginx.arn
}

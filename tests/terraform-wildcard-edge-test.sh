#!/bin/bash

set -euo pipefail

assert_contains() {
    local file="$1"
    local pattern="$2"

    if ! grep -Fq -- "$pattern" "$file"; then
        echo "missing expected pattern in $file: $pattern" >&2
        exit 1
    fi
}

assert_not_contains() {
    local file="$1"
    local pattern="$2"

    if grep -Fq -- "$pattern" "$file"; then
        echo "unexpected pattern in $file: $pattern" >&2
        exit 1
    fi
}

assert_contains terraform/backend.tf 'backend "s3"'
assert_contains terraform/backend.tf 'bucket         = "dame-tfstate-apse2"'
assert_contains terraform/backend.tf 'dynamodb_table = "dame-tf-locks"'

assert_contains terraform/variables.tf 'variable "wildcard_domain_name"'
assert_contains terraform/variables.tf 'variable "existing_alb_name"'
assert_contains terraform/variables.tf 'variable "existing_https_listener_port"'
assert_contains terraform/variables.tf 'variable "ingress_target_ips"'
assert_not_contains terraform/variables.tf 'variable "k8s_worker_nodes"'
assert_not_contains terraform/variables.tf 'variable "k8s_nodeport"'
assert_not_contains terraform/variables.tf 'variable "health_check_path"'
assert_not_contains terraform/variables.tf 'variable "health_check_port"'
assert_not_contains terraform/variables.tf 'variable "teams_webhook_path"'
assert_not_contains terraform/variables.tf 'variable "vpc_id"'

assert_contains terraform/main.tf 'data "aws_lb" "existing"'
assert_contains terraform/main.tf 'data "aws_lb_listener" "https"'
assert_contains terraform/main.tf 'resource "aws_lb_listener_certificate" "wildcard"'
assert_contains terraform/main.tf 'resource "aws_lb_target_group" "ingress_nginx"'
assert_contains terraform/main.tf 'resource "aws_lb_target_group_attachment" "ingress_targets"'
assert_contains terraform/main.tf 'resource "aws_lb_listener_rule" "wildcard_hosts"'
assert_contains terraform/main.tf 'values = [var.wildcard_domain_name]'
assert_not_contains terraform/main.tf 'resource "aws_lb" "openclaw"'
assert_not_contains terraform/main.tf 'resource "aws_security_group" "openclaw_alb"'
assert_not_contains terraform/main.tf 'resource "aws_security_group" "openclaw_k8s_alb_ingress"'
assert_not_contains terraform/main.tf 'resource "aws_lb_target_group" "openclaw_k8s_teams"'
assert_not_contains terraform/main.tf 'resource "aws_lb_target_group_attachment" "k8s_nodes"'
assert_not_contains terraform/main.tf 'resource "aws_lb_listener" "https"'
assert_not_contains terraform/main.tf 'resource "aws_lb_listener" "http"'
assert_not_contains terraform/main.tf 'resource "aws_lb_listener_rule" "teams_webhook"'

assert_contains terraform/acm-certificate.tf 'domain_name       = var.wildcard_domain_name'
assert_contains terraform/acm-certificate.tf 'resource "aws_acm_certificate_validation" "wildcard"'
assert_contains terraform/route53.tf 'name    = var.wildcard_domain_name'
assert_contains terraform/route53.tf 'name                   = data.aws_lb.existing.dns_name'
assert_contains terraform/route53.tf 'zone_id                = data.aws_lb.existing.zone_id'

assert_not_contains terraform/k8s-service.tf 'resource "kubernetes_service" "openclaw_teams_webhook"'

assert_contains terraform/terraform.tfvars.example 'wildcard_domain_name = "*.openclaw.dametech.net"'
assert_contains terraform/terraform.tfvars.example 'existing_alb_name = "openclaw-alb"'
assert_contains terraform/terraform.tfvars.example 'existing_https_listener_port = 443'
assert_contains terraform/terraform.tfvars.example 'ingress_target_ips = ['

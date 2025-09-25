output "alb_dns" {
  description = "DNS of the ALB"
  value       = aws_lb.app_alb.dns_name
}

output "app_public_ip" {
  description = "App EC2 Public IP"
  value       = aws_instance.app.public_ip
}

output "scylla_private_ip" {
  description = "Scylla EC2 Private IP"
  value       = aws_instance.scylla.private_ip
}

output "redis_private_ip" {
  description = "Redis EC2 Private IP"
  value       = aws_instance.redis.private_ip
}

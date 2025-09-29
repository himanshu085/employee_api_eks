output "cluster_name" {
  description = "EKS Cluster Name"
  value       = aws_eks_cluster.this.name
}

output "cluster_endpoint" {
  description = "EKS Cluster Endpoint"
  value       = aws_eks_cluster.this.endpoint
}

output "node_group_name" {
  description = "EKS Node Group Name"
  value       = aws_eks_node_group.employee_nodes.node_group_name
}

output "employee_api_service_dns" {
  description = "DNS name of Employee API Service"
  value       = kubernetes_service.employee_api.status[0].load_balancer[0].ingress[0].hostname
}


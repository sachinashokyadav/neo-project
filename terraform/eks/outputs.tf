output "cluster_name" {
  value = aws_eks_cluster.this.name
}

output "cluster_endpoint" {
  value = aws_eks_cluster.this.endpoint
}

output "cluster_cert" {
  value = aws_eks_cluster.this.certificate_authority[0].data
}

output "kubeconfig_command" {
  value = "aws eks update-kubeconfig --region ${var.region} --name ${aws_eks_cluster.this.name}"
}

output "frontend_node_group" {
  value = aws_eks_node_group.frontend.node_group_name
}

output "backend_node_group" {
  value = aws_eks_node_group.backend.node_group_name
}

output "database_node_group" {
  value = aws_eks_node_group.database.node_group_name
}


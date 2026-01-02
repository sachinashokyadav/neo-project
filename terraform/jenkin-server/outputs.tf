output "jenkins_url" {
  value = "http://${aws_instance.jenkins_server.public_ip}:8080"
}

output "jenkins_server_ip" {
  value = aws_instance.jenkins_server.public_ip
}

output "jenkins_agent_ip" {
  value = aws_instance.jenkins_agent.public_ip
}


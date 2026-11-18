output "instances" {
  description = "Hostname => private und aktuelle öffentliche IP"
  value = {
    for name, vm in aws_instance.vm : name => {
      private_ip = vm.private_ip
      public_ip  = vm.public_ip
    }
  }
}

output "ssh_commands" {
  description = "SSH-Befehle (nach Stopp/Start vorher: terraform apply -refresh-only)"
  value       = { for name, vm in aws_instance.vm : name => "ssh ubuntu@${vm.public_ip}" }
}

output "gitlab_url" {
  description = "GitLab von den Team-PCs (Hosts-Eintrag: <IP> gitlab.cicd.internal)"
  value       = "https://${aws_instance.vm["gitlab"].public_ip}"
}

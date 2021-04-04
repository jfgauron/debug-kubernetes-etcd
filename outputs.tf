output "lb_dns" {
  value = aws_lb.nlb.dns_name
}

output "bastion" {
  value = aws_instance.bastion.public_dns
}

output "master1" {
  value = aws_instance.master1.private_ip
}

output "master2" {
  value = aws_instance.master2.private_ip
}
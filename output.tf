output "ip" {
  value = "${aws_eip.k3s-master-ip.public_ip}"
}

output "info" {
  value = "UI url: http://${aws_eip.k3s-master-ip.public_ip}"
}


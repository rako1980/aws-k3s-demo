output "ip" {
  value = "${aws_eip.k3s-master-ip.public_ip}"
}


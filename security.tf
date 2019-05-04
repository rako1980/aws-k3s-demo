resource "aws_security_group" "k3s-sg" {

name = "k3s-ssh-sg"

vpc_id = "${aws_vpc.signalpath.id}"

ingress {
    cidr_blocks = [
      "0.0.0.0/0"
    ]

from_port = 22
    to_port = 22
    protocol = "tcp"
  }

  egress {
   from_port = 0
   to_port = 0
   protocol = "-1"
   cidr_blocks = ["0.0.0.0/0"]
 }

}

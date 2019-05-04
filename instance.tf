resource "aws_instance" "k3s-master-node" {
  ami           = "${var.ami}"
  instance_type = "${var.instance_type}"
  key_name = "${aws_key_pair.deployer.key_name}"
  security_groups = ["${aws_security_group.k3s-sg.id}"]

subnet_id = "${aws_subnet.k3s-subnet.id}"

}

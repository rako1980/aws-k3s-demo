# ---------------------------------------------------------------------------------------------------
# Deploy an EC2 instance and then invoke a provisioner
# ---------------------------------------------------------------------------------------------------

# --------------------------------------------------------------------------------------------------
# Define a provider access and import your publick key
# ---------------------------------------------------------------------------------------------------
provider "aws" {
  access_key = "${var.access_key}"
  secret_key = "${var.secret_key}"
  region     = "${var.region}"
}

resource "aws_key_pair" "deployer" {
  key_name   = "k3s-setup-key"
  public_key = "${var.ssh_rsa_pub}"
}

# -----------------------------------------------------------------------------------------------------
# Deploy an EC2 instance and invoke ansible 
# ---------------------------------------------------------------------------------------------
resource "aws_instance" "k3s-master-node" {
  ami           = "${var.ami}"
  instance_type = "${var.instance_type}"
  key_name = "${aws_key_pair.deployer.key_name}"
  security_groups = ["${aws_security_group.k3s-sg.id}"]

subnet_id = "${aws_subnet.k3s-subnet.id}"

}

# --------------------------------------------------------------------------------------------------------
# Networking: Define the VPC, subnet, inetrnet gateway. routing table and elastic IP for the ec2 instance 
# --------------------------------------------------------------------------------------------------------

resource "aws_vpc" "signalpath" {
  cidr_block = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support = true
  tags {
    Name = "raj-assignment"
  }
}

resource "aws_subnet" "k3s-subnet" {
  cidr_block = "${cidrsubnet(aws_vpc.signalpath.cidr_block, 3, 1)}"
  vpc_id = "${aws_vpc.signalpath.id}"
  availability_zone = "${var.region}a"
}

resource "aws_internet_gateway" "k3s-gateway" {
  vpc_id = "${aws_vpc.signalpath.id}"
}


resource "aws_route_table" "route-table-signalpath" {
  vpc_id = "${aws_vpc.signalpath.id}"

route {
    cidr_block = "0.0.0.0/0"
    gateway_id = "${aws_internet_gateway.k3s-gateway.id}"
  }
}

resource "aws_route_table_association" "subnet-association" {
  subnet_id      = "${aws_subnet.k3s-subnet.id}"
  route_table_id = "${aws_route_table.route-table-signalpath.id}"
}

resource "aws_eip" "k3s-master-ip" {
  instance = "${aws_instance.k3s-master-node.id}"
}


# -----------------------------------------------------------------------------------------------
# Security groups: Alow all egress traffic, only allow ssh ingress traffic on the VPC
# -------------------------------------------------------------------------------------------------

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

# ---------------------------------------------------------------------------------------------
# Run provisioner:
# ----------------------------------------------------------------------------------------------

resource "null_resource" "connection_ec2" {
  connection {
    host  =  "${aws_eip.k3s-master-ip.public_ip}"
    user = "ec2-user"
    private_key = "${file("~/.ssh/id_rsa")}"
  }
  provisioner "remote-exec" {
    inline = [
      "sudo yum install python -y",
      "sudo mkdir -p /etc/ansible/facts.d && sudo echo '[terraform]\n'`date` > /etc/ansible/facts.d/terraform",
    ]
  }
  depends_on = ["aws_eip.k3s-master-ip"]
}

 


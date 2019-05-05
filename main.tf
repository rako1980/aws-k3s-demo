# ---------------------------------------------------------------------------------------------------
# Deploy an EC2 instance and then invoke a provisioner to execute ansible playbook
# terraform: Infrastructure deployement 
# -- network: 1 - vpc,subnet,gateway, routing table,  security group
# -- instance: 1 ec2, 1 eip
# -- provisioner: ansible-playbook (k3s and consul install)
# ---------------------------------------------------------------------------------------------------

# ---------------------------------------------------------------------------------------------------
# Define a provider access and import your public key
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
# Deploy an EC2 instance
# -----------------------------------------------------------------------------------------------------
resource "aws_instance" "k3s-master-node" {
  ami           = "${var.ami}"
  instance_type = "${var.instance_type}"
  key_name = "${aws_key_pair.deployer.key_name}"
  security_groups = ["${aws_security_group.k3s-sg.id}"]

subnet_id = "${aws_subnet.k3s-subnet.id}"

}

# -----------------------------------------------------------------------------------------------------
# Networking: Define the VPC, subnet, internet gateway. routing table and eio for ec2 instance 
# -----------------------------------------------------------------------------------------------------

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


# -----------------------------------------------------------------------------------------------------
# Security groups: Alow all egress traffic, only allow ssh,http(s) ingress traffic on the VPC
# -----------------------------------------------------------------------------------------------------

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
ingress {
  cidr_blocks = [
    "0.0.0.0/0"
  ]
  from_port = 80
  to_port = 80
  protocol = "tcp"
}
ingress {
  cidr_blocks = [
    "0.0.0.0/0"
  ]
  from_port = 443
  to_port = 443
  protocol = "tcp"
}

egress {
   from_port = 0
   to_port = 0
   protocol = "-1"
   cidr_blocks = ["0.0.0.0/0"]
 }

}

# -----------------------------------------------------------------------------------------------------
# Run provisioner: pretasks and invoke ansible playbook for k3s and consul deployment
# -----------------------------------------------------------------------------------------------------

resource "null_resource" "connection_ec2" {
  connection {
    host  =  "${aws_eip.k3s-master-ip.public_ip}"
    user = "ec2-user"
    private_key = "${file("~/.ssh/id_rsa")}"
  }
 
  # -- Populate the ansible inventory with its public IP
  provisioner "local-exec" {
    command = "printf '[k3sdemo]\n${aws_eip.k3s-master-ip.public_ip}' > ./inventory/hosts"
  }
 
  # -- Fulfill some prereq for the new instance
  provisioner "remote-exec" {
    inline = [
      "sudo yum update -y",
      "sudo yum install python -y",
    ]
  }

  # -- Invoke the ansible playbook provision.yml - setup k3s single master/node environment
  # -- and deploy consul helm chart
  provisioner "local-exec" {
    command = "ansible-playbook -i ./inventory/hosts -l ${aws_eip.k3s-master-ip.public_ip} provision.yml"
  }


  depends_on = ["aws_eip.k3s-master-ip"]
}

 


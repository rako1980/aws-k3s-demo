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


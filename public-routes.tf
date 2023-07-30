## This thing generates public subnets in all AZs and attaches them to the internet gateway

locals {
  SUBNET_ZONES = [
    "eu-central-1a",
    "eu-central-1b",
    "eu-central-1c"
  ]
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.My-VPC.id
  tags   = { Name = "igw" }
}

resource "aws_internet_gateway_attachment" "igw" {
  vpc_id              = aws_vpc.My-VPC.id
  internet_gateway_id = aws_internet_gateway.igw.id
}

resource "aws_subnet" "public" {
  count                   = length(local.SUBNET_ZONES)
  vpc_id                  = aws_vpc.My-VPC.id
  cidr_block              = cidrsubnet(aws_vpc.My-VPC.cidr_block, 8, 20 + count.index)
  availability_zone       = local.SUBNET_ZONES[count.index]
  map_public_ip_on_launch = true
}

resource "aws_route_table" "public-rtb" {
  vpc_id = aws_vpc.My-VPC.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
}

resource "aws_route_table_association" "public-rtb-assoc" {
  count          = length(local.SUBNET_ZONES)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public-rtb.id
}
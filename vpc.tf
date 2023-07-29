resource "aws_vpc" "My-VPC" {
  cidr_block = "10.100.0.0/16"
  assign_generated_ipv6_cidr_block = true
  enable_dns_hostnames = true
  enable_dns_support = true
  tags = {
    Name = "My-VPC"
  }
}

resource "aws_subnet" "private" {
  vpc_id            = aws_vpc.My-VPC.id
  availability_zone = "eu-central-1b"
  cidr_block        = "10.100.1.0/24"
  ipv6_cidr_block   = cidrsubnet(aws_vpc.My-VPC.ipv6_cidr_block, 8, 1)
}
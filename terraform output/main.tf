provider "aws" {
    region = "ap-south-1"
    access_key = "xxxx"
    secret_key = "xxxx"
}

resource "aws_vpc" "development-vpc" {
    cidr_block = "10.0.0.0/16"
}

resource "aws_subnet" "dev_subnet" {
  vpc_id = aws_vpc.development-vpc.id
  cidr_block = "10.0.1.0/24"
  availability_zone = "ap-south-1a" 
}

data "aws_vpc" "existing_vpc" {
    default = true
}

resource "aws_subnet" "dev-subnet-1" {
    vpc_id = data.aws_vpc.existing_vpc.id
    cidr_block = "172.31.48.0/20" 
    availability_zone = "ap-south-1a" 
}

output "dev-subnet-id" {
    value = aws_subnet.dev_subnet.id 
}

output "aws-vpc-id" {
    value = aws_vpc.development-vpc.id 
}

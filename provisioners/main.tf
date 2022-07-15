provider "aws" {
    region = "ap-south-1"
}

# variables

variable "vpc_cidr_block" {}
variable "subnet_cidr_block" {}
variable "avail_zone" {}
variable "env_prefix" {}
variable "my-ip" {}
variable "instance_type" {}
variable "local_public_key_location" {}
variable "private_key_location" {}

# create a vpc

resource "aws_vpc" "myapp-vpc" {
   cidr_block = var.vpc_cidr_block
   tags = {
    Name: "${var.env_prefix}-vpc"
   }
} 

# create a subnet

resource "aws_subnet" "myapp_subnet-1" {
  vpc_id = aws_vpc.myapp-vpc.id
  cidr_block = var.subnet_cidr_block
  availability_zone = var.avail_zone 
  tags = {
    Name = "${var.env_prefix}-subnet-1"
  }
}

# create a new route table

resource "aws_route_table" "myapp-route-table" {

# it will be created under the same VPC so we paste the same ID as in aws_subnet

    vpc_id = aws_vpc.myapp-vpc.id

# we're going to create a second entry in out route block which basically is internet gateway

    route {
        cidr_block = "0.0.0.0/0"
        gateway_id = aws_internet_gateway.myapp-igw.id
    }
    tags = {
      Name: "${var.env_prefix}-rtb"
    }
}

# in our vpc we dont have the resource for internet gateway, so we'll create it
resource "aws_internet_gateway" "myapp-igw" {
    vpc_id = aws_vpc.myapp-vpc.id  
    tags = {
      "Name" = "${var.env_prefix}-igw"
    }
}

resource "aws_route_table_association" "a-rtb-subnet" {
      subnet_id = aws_subnet.myapp_subnet-1.id
      route_table_id = aws_route_table.myapp-route-table.id
}

# if we want to use the default route table instead of creating a new one,
# for that we remove the (resource "aws_route_table_association") and
# (resource "aws_route_table"),
# and use the below defined resource. 

/*resource "aws_default_route_table" "main-rtb" {
    default_route_table_id = aws_vpc.myapp-vpc.default_route_table_id

    route {
        cidr_block = "0.0.0.0/16"
        gateway_id = aws_internet_gateway.myapp-igw.id
    }
    tags = {
      "Name" = "${var.env_prefix}-main-rtb"
    }
  
}*/

# next we will configure the firewall rules for our ec2 instance, so we can access to it using SSH on port 22
# as well as the nginx server on port 8080 

# to use the default security group, just modify the name by "aws_default_security_group" and "default-sg"
# remove the "name(key:pair)" in resource, because its default so we don't have to define it

resource "aws_security_group" "myapp-sg" {
    name = "myapp-sg"
    vpc_id = aws_vpc.myapp-vpc.id

# generally we have two types of rules, that being traffic coming inside the vpc and then entering the server
# and the incoming traffic use a rule called "INGRESS"

    ingress {
        from_port = 22
        to_port = 22              # here we are configuring a single port 22, but we can also set a range (from_port - to_port)
        protocol = "TCP"
        cidr_blocks = [var.my-ip]  # accessing a server on SSH should be secure, so we allow some IP addr permitted to do that
    }    

    ingress {
        from_port = 8080
        to_port = 8080
        protocol = "TCP"
        cidr_blocks = ["0.0.0.0/0"] 
    }

    egress {
        from_port = 0                     # we don't want to restrict any outgoing request
        to_port = 0                       # we don't want to restrict any outgoing request
        protocol = "-1"                   # we dont want to restrict the protocol  
        cidr_blocks = ["0.0.0.0/0"] 
        prefix_list_ids = []              # to allow accessing VPC endpoints
    } 

    tags = {
        Name = "${var.env_prefix}-sg"     # for default security group "${var.env_prefix}-default-sg"
    }   
}

# now we create an EC2 instance, first we declare the "data" then the "resource"

data "aws_ami" "latest-ami" {
    most_recent = true  
    owners = ["amazon"]
    filter {
        name = "name"
        values = ["amzn2-ami-hvm-*-x86_64-gp2"]
    }
    filter {
        name = "virtualization-type"
        values = ["hvm"]
    }
}

# we don't want to create a key manually everytime(such a drag), so we automate that by creating a resource

resource "aws_key_pair" "ssh-key" {
    key_name = "my-server-key"

# we can mention the key here but its not best practice, opt#2 to mention in a variable file,
# opt#3 reference the file location     

    public_key = "${file(var.local_public_key_location)}"  # we can use file(var.------location) without "${}" because this is not a string, so no interpolation 
}

resource "aws_instance" "myapp-server" {
    ami = data.aws_ami.latest-ami.id
    instance_type = var.instance_type
    
    subnet_id = aws_subnet.myapp_subnet-1.id
    vpc_security_group_ids = [aws_security_group.myapp-sg.id]
    availability_zone = var.avail_zone

    associate_public_ip_address = true
    key_name = aws_key_pair.ssh-key.key_name

    connection {
        type = "ssh"
        host = self.public_ip
        user = "ec2-user"
        private_key = file(var.private_key_location)
    }

# !!WARNING!!
# TERRAFORM doesn't promote the use of provisioners, it's just a workaround if things doesn't work.
# If provisioner fails to copy this script to remote or if it is not found on local to be copied then terraform marks the whole process as failed
# and then we might have to create the whole server again.   
 
    provisioner "file" {
        source = "entry_script.sh"      # this is how we copy a file from local-to-remote
        destination = "/home/ec2-user/entry_script-on-ec2.sh"
    
    }  

# if we want to copy this file to some other server

    /*provisioner "file" {
        source = "entry_script.sh"      # this is how we copy a file from local-to-remote
        destination = "/home/ec2-user/entry_script-on-ec2.sh"

        connection {
        type = "ssh"
        host = someotherserver.public_ip
        user = "ec2-user"
        private_key = file(var.private_key_location)
    }*/

# to mention the shell commands to run when a server is created/provisioned (below)
# we add the below mentioned syntax in the "provisioner "remote-exec" with proper indent

                                /*inline = [
                                    "sudo yum update",
                                    "sudo yum install update -y",
                                    "sudo yum install -y docker"
                                ]*/

    provisioner "remote-exec" {
        
    
# or we use a script attribute

        script = file("entry_script-on-ec2.sh")  # this means the ".sh" must already exist on the server for it to be executed
      
    }

# if we want to run some command on the local system then we follow :-

    provisioner "local-exec" {
        command = "echo ${self.public_id}" > public_ip.txt
    }

    tags = {
        Name = "${var.env_prefix}-server"
    }
}

output "aws_ami_id" {
    value = data.aws_ami.latest-ami.id
}

output "ec2_public-ip" {
    value = aws_instance.myapp-server.public_ip
}

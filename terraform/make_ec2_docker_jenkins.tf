provider "aws" {
  region     = "us-east-1"
  access_key = ""
  secret_key = ""
}



/* for some reason this parts returns an error always on the 1st run, 2nd 'terraform plan' works fine*/
data "external" "generate_ssh_key" {
  program = ["bash", "-c", <<-EOF
    mkdir -p ${path.module}/.ssh
    if [ ! -f ${path.module}/.ssh/id_rsa.pub ]; then
      ssh-keygen -t rsa -b 2048 -f ${path.module}/.ssh/id_rsa -N ''
    fi
    cat ${path.module}/.ssh/id_rsa.pub | jq -R '{public_key: .}'
  EOF
  ]
}

resource "aws_key_pair" "auth" {
  key_name   = "ec2-key-pair"
  public_key = data.external.generate_ssh_key.result["public_key"]
}




resource "aws_security_group" "sg_dockerJenkinsInstance" {
  name        = "sg_dockerJenkinsInstance"
  description = "SG - opens 22 and 8080"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "dockerJenkinsInstance" {
  ami           = "ami-0c101f26f147fa7fd"
  instance_type = "t2.micro"
  key_name      = aws_key_pair.auth.key_name
  security_groups = [aws_security_group.sg_dockerJenkinsInstance.name]


  root_block_device {
    volume_type           = "gp2"
    volume_size           = 12
    delete_on_termination = false
  }


  user_data = <<-EOF
                #!/bin/bash
                yum update -y >> ud_upd_out.txt
                yum install -y docker >> ud_dock_ins.txt
                
                # Station name:
                hostnamectl set-hostname dockerJenkins

                # Docker and boot init
                service docker start
                systemctl enable docker

                # Jenkins w/ restart option so it always boot w/ station - sock allows for communication with host.
                # docker run -d -p 8080:8080 -p 50000:50000 -v jenkins_home:/var/jenkins_home jenkins/jenkins:lts
                # docker run -d --restart unless-stopped -p 8080:8080 -p 50000:50000 -v jenkins_home:/var/jenkins_home jenkins/jenkins:lts >> ud_jenk_out.txt
                docker run -d --restart unless-stopped -v /var/run/docker.sock:/var/run/docker.sock -v jenkins_home:/var/jenkins_home -p 8080:8080 -p 50000:50000 jenkins/jenkins:lts >> ud_jenk_out.txt
                chmod 666 /var/run/docker.sock
                
                EOF


  tags = {
    Name = "DockerAndJenkins"
  }
}



resource "aws_eip" "dockerJenkinsInstance" {
  instance = aws_instance.dockerJenkinsInstance.id
  domain      = "vpc"
}


output "instance_ip" {
  value = aws_eip.dockerJenkinsInstance.public_ip
}
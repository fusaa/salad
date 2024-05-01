provider "aws" {
  region     = "us-east-1"
  access_key = ""
  secret_key = ""
}



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




resource "aws_security_group" "sg_k8s" {
  name        = "sg_k8s"
  description = "SG - k8s"

  ingress {
    from_port   = 22
    to_port     = 22
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

resource "aws_instance" "k8sInstance" {
  ami           = "ami-0c101f26f147fa7fd"
  instance_type = "t2.medium"
  key_name      = aws_key_pair.auth.key_name
  security_groups = [aws_security_group.sg_k8s.name]


  root_block_device {
    volume_type           = "gp2"
    volume_size           = 12
    delete_on_termination = false
  }


  user_data = <<-O_EOF
                #!/bin/bash
                yum update -y
                yum install -y docker          
                hostnamectl set-hostname k8sInstance

                # Docker and boot init
                service docker start
                systemctl enable docker

                # Creating K8s repo config file
                cat <<-I_EOF | sudo tee /etc/yum.repos.d/kubernetes.repo
                [kubernetes]
                name=Kubernetes
                baseurl=https://pkgs.k8s.io/core:/stable:/v1.29/rpm/
                enabled=1
                gpgcheck=1
                repo_gpgcheck=1
                gpgkey=https://pkgs.k8s.io/core:/stable:/v1.29/rpm/repodata/repomd.xml.key 
                I_EOF

                # Kubernetes tools:
                yum install -y kubelet kubeadm kubectl



                # Disable swap and disable startup swap fstab
                swapoff -a
                sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab

                # kubelet service (enable+init)
                systemctl enable --now kubelet

                # traffic control/issue
                yum install iproute-tc -y

                # Init master
                kubeadm init --pod-network-cidr=10.240.0.0/16 --ignore-preflight-errors=NumCPU,Mem
                
                # Export the KUBECONFIG
                export KUBECONFIG=/etc/kubernetes/admin.conf
                
                
                O_EOF



  tags = {
    Name = "k8sInstance"
  }
}



resource "aws_eip" "k8sInstance" {
  instance = aws_instance.k8sInstance.id
  domain      = "vpc"
}


output "instance_ip" {
  value = aws_eip.k8sInstance.public_ip
}

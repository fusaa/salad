
resource "aws_instance" "k8sInstance_node1" {
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
                hostnamectl set-hostname k8sInstance_node1

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


                
                O_EOF


  tags = {
    Name = "k8sInstance_node1"
  }
}



resource "aws_eip" "k8sInstance_node1" {
  instance = aws_instance.k8sInstance_node1.id
  domain      = "vpc"
}


output "instance_ip_node1" {
  value = aws_eip.k8sInstance_node1.public_ip
}
#!/bin/bash


#1. install yq
BINARY=yq_linux_amd64
VERSION=v4.8.0 
wget https://github.com/mikefarah/yq/releases/download/${VERSION}/${BINARY} -O /usr/bin/yq &&  chmod +x /usr/bin/yq


#2. install yq calicoctl 
curl -o /usr/bin/calicoctl -O -L https://github.com/projectcalico/calicoctl/releases/download/v3.18.4/calicoctl &&   chmod +x /usr/bin/calicoctl


#3. install CNI plugins (required for most pod network)
CNI_VERSION="v0.8.2"
sudo mkdir -p /opt/cni/bin
curl -L "https://github.com/containernetworking/plugins/releases/download/${CNI_VERSION}/cni-plugins-linux-amd64-${CNI_VERSION}.tgz" | sudo tar -C /opt/cni/bin -xz


#4. install kubeadm, kubelet, kubectl
RELEASE="v1.19.7"
curl -o /usr/bin/kubeadm https://storage.googleapis.com/kubernetes-release/release/${RELEASE}/bin/linux/amd64/kubeadm && chmod +x /usr/bin/kubeadm
curl -o /usr/bin/kubelet https://storage.googleapis.com/kubernetes-release/release/${RELEASE}/bin/linux/amd64/kubelet && chmod +x /usr/bin/kubelet
curl -o /usr/bin/kubectl https://storage.googleapis.com/kubernetes-release/release/${RELEASE}/bin/linux/amd64/kubectl && chmod +x /usr/bin/kubectl

#5. add a kubelet systemd service
RELEASE_VERSION="v0.4.0"
curl -sSL "https://raw.githubusercontent.com/kubernetes/release/${RELEASE_VERSION}/cmd/kubepkg/templates/latest/deb/kubelet/lib/systemd/system/kubelet.service" | sudo tee /etc/systemd/system/kubelet.service
sudo mkdir -p /etc/systemd/system/kubelet.service.d
curl -sSL "https://raw.githubusercontent.com/kubernetes/release/${RELEASE_VERSION}/cmd/kubepkg/templates/latest/deb/kubeadm/10-kubeadm.conf" | sudo tee /etc/systemd/system/kubelet.service.d/10-kubeadm.conf


#6. enable and start kubelet
systemctl enable --now kubelet

#7. install subctl
curl -Ls https://get.submariner.io | bash
export PATH=$PATH:~/.local/bin
echo export PATH=\$PATH:~/.local/bin >> ~/.profile


rm -rf broker-info.subm
 kubeadm reset -f 

kubeadm init --apiserver-advertise-address=10.0.0.80 --apiserver-cert-extra-sans=localhost,127.0.0.1,10.0.0.80,132.232.31.102 --pod-network-cidr=10.44.0.0/16 --service-cidr=10.45.0.0/16 --kubernetes-version v1.19.7

sudo cp -f /etc/kubernetes/admin.conf $HOME/.kube/config

yq -i eval \
'.clusters[].cluster.server |= sub("10.0.0.80", "132.232.31.102") | .contexts[].name = "cluster-a" | .current-context = "cluster-a"' \
$HOME/.kube/config

sleep 60

kubectl label node vm-0-80-ubuntu submariner.io/gateway=true
kubectl taint nodes --all node-role.kubernetes.io/master-

kubectl apply -f https://docs.projectcalico.org/manifests/calico.yaml

sleep 120

DATASTORE_TYPE=kubernetes calicoctl create -f /root/cluster1.yaml

subctl deploy-broker 

sleep 60

scp  broker-info.subm 139.155.48.141:/root
scp  broker-info.subm 129.226.144.251:/root
subctl join broker-info.subm --clusterid cluster-a --natt=true

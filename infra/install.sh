#!/bin/bash

echo "🚀 Iniciando instalação das ferramentas necessárias..."

# Função para verificar se comando existe
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Instalar dependências básicas
echo "📦 Instalando dependências básicas..."
sudo apt update
sudo apt install -y git docker.io curl unzip

# Docker
echo "🐳 Configurando Docker..."
if ! command_exists docker; then
    sudo systemctl start docker
    sudo systemctl enable docker
    sudo usermod -aG docker $USER
    newgrp docker
fi

# kubectl
echo "☸️ Instalando kubectl..."
if ! command_exists kubectl; then
    curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
    sudo install -o root -g root -m 0755 kubectl /usr/local/bin/
    rm kubectl
fi

# Minikube
echo "🔄 Instalando Minikube..."
if ! command_exists minikube; then
    curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
    sudo install minikube-linux-amd64 /usr/local/bin/minikube
    rm minikube-linux-amd64
fi

# ArgoCD CLI
echo "🎯 Instalando ArgoCD CLI..."
if ! command_exists argocd; then
    curl -sLO https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
    sudo install -o root -g root -m 0755 argocd-linux-amd64 /usr/local/bin/argocd
    rm argocd-linux-amd64
fi

# Instalar
echo "🔧 Instalando Jenkins..."
curl -fsSL https://pkg.jenkins.io/debian-stable/jenkins.io-2023.key | sudo tee \
    /usr/share/keyrings/jenkins-keyring.asc > /dev/null

echo deb [signed-by=/usr/share/keyrings/jenkins-keyring.asc] \
    https://pkg.jenkins.io/debian-stable binary/ | sudo tee \
    /etc/apt/sources.list.d/jenkins.list > /dev/null

sudo apt-get update
sudo apt-get install -y jenkins

# Garantir que Jenkins tenha acesso ao Docker
sudo usermod -aG docker jenkins
sudo systemctl restart jenkins

# Iniciar Minikube
echo "🚀 Iniciando Minikube..."
minikube start --driver=docker

# Habilitar ingress
echo "🔌 Habilitando Ingress no Minikube..."
minikube addons enable ingress

# Configurar registry local
echo "📦 Configurando registry local..."
docker run -d -p 5000:5000 --name registry registry:2

# Instalar ArgoCD no cluster
echo "🎯 Instalando ArgoCD no cluster..."
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

echo "✅ Instalação concluída! Por favor, siga as instruções no README.md para:"
echo "  1. Fazer fork dos repositórios"
echo "  2. Configurar credenciais do GitHub no Jenkins"
echo "  3. Configurar Jenkins"
echo "  4. Configurar ArgoCD" 
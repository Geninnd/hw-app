#!/usr/bin/env bash
set -euo pipefail

echo "🚀 Iniciando instalação das ferramentas necessárias..."

# Função para checar existência de comando
command_exists() { command -v "$1" >/dev/null 2>&1; }

echo "📦 Atualizando repositórios e instalando pacotes básicos..."
sudo apt update
sudo apt install -y git docker.io curl unzip

echo "🐳 Habilitando e configurando Docker..."
sudo systemctl enable --now docker
sudo usermod -aG docker "$USER"

# kubectl
if ! command_exists kubectl; then
  echo "☸️ Instalando kubectl..."
  K8S_VER="v1.26.3"  # Versão estável específica
  curl -LO "https://dl.k8s.io/release/${K8S_VER}/bin/linux/amd64/kubectl"
  sudo install kubectl /usr/local/bin/
  rm kubectl
fi

# Minikube
if ! command_exists minikube; then
  echo "🔄 Instalando Minikube..."
  curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
  sudo install minikube-linux-amd64 /usr/local/bin/minikube
  rm minikube-linux-amd64
fi

# ArgoCD CLI
if ! command_exists argocd; then
  echo "🎯 Instalando ArgoCD CLI..."
  curl -sLO https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
  sudo install argocd-linux-amd64 /usr/local/bin/argocd
  rm argocd-linux-amd64
fi

# Parar e remover Minikube existente
echo "🧹 Limpando instalação anterior do Minikube..."
minikube stop || true
minikube delete || true

# Iniciar Minikube com configuração específica
echo "🚀 Iniciando Minikube..."
minikube start \
  --driver=docker \
  --kubernetes-version=v1.26.3 \
  --memory=4096 \
  --cpus=2 \
  --addons=storage-provisioner \
  --addons=default-storageclass

# Aguardar o API server ficar ativo
echo "⌛ Aguardando API server (até 120s)..."
kubectl wait --for=condition=Ready nodes --all --timeout=120s

# Habilitar Ingress
echo "🔌 Habilitando addon ingress no Minikube..."
minikube addons enable ingress || echo "    -> Falha ignorada ao habilitar ingress"

# Registry local
echo "📦 Configurando registry local..."
if ! docker ps --format '{{.Names}}' | grep -q '^registry$'; then
  docker run -d --restart=always -p 5000:5000 --name registry registry:2
fi

# Instalar ArgoCD no cluster
echo "🎯 Instalando ArgoCD no cluster..."
kubectl get ns argocd >/dev/null 2>&1 || kubectl create ns argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Jenkins via Docker
echo "🔧 Configurando Jenkins em container Docker..."
docker volume create jenkins_home >/dev/null || true

docker rm -f jenkins >/dev/null 2>&1 || true

# Criar container Jenkins
docker run -d \
  --name jenkins \
  --restart=unless-stopped \
  -p 8080:8080 -p 50000:50000 \
  -v jenkins_home:/var/jenkins_home \
  -v /var/run/docker.sock:/var/run/docker.sock \
  --user root \
  jenkins/jenkins:lts-jdk11

# Aguardar container iniciar
echo "⏳ Aguardando Jenkins iniciar (30s)..."
sleep 30

# Ajustar permissões
echo "🔧 Ajustando permissões..."
docker exec jenkins chown -R jenkins:jenkins /var/jenkins_home

echo "✅ Instalação concluída!"
echo "Acesse Jenkins: http://localhost:8080"
echo "Para obter a senha inicial do Jenkins, execute:"
echo "docker exec jenkins cat /var/jenkins_home/secrets/initialAdminPassword"

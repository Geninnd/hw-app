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
if docker ps --format '{{.Names}}' | grep -q '^minikube$'; then
  minikube stop
fi
minikube delete --all --purge >/dev/null 2>&1 || true

# Iniciar Minikube com configuração específica
echo "🚀 Iniciando Minikube com registro inseguro..."
minikube start \
  --driver=docker \
  --kubernetes-version=v1.26.3 \
  --memory=4096 \
  --cpus=2 \
  --addons=storage-provisioner \
  --addons=default-storageclass \
  --insecure-registry="localhost:5000"

# Obter IP do Minikube para o Jenkins
echo "🔗 Obtendo IP do Minikube..."
MINIKUBE_IP=$(minikube ip)
echo "    -> IP do Minikube: ${MINIKUBE_IP}"

# Aguardar o API server ficar ativo
echo "⌛ Aguardando API server (até 120s)..."
kubectl wait --for=condition=Ready nodes --all --timeout=120s

# Habilitar Ingress
echo "🔌 Habilitando addon ingress no Minikube..."
minikube addons enable ingress || echo "    -> Falha ignorada ao habilitar ingress"

# Registry local dentro do Minikube
echo "📦 Configurando registry local dentro do Minikube..."
if ! minikube ssh "docker ps --format '{{.Names}}'" | grep -q '^registry$'; then
    minikube ssh -- "docker run -d -p 5000:5000 --restart=always --name registry registry:2"
fi

# Instalar ArgoCD no cluster
echo "🎯 Instalando ArgoCD no cluster..."
kubectl get ns argocd >/dev/null 2>&1 || kubectl create ns argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Criar namespace da aplicação
echo "🏗️  Criando namespace da aplicação 'hw-app'..."
kubectl get ns hw-app >/dev/null 2>&1 || kubectl create ns hw-app

# Jenkins via Docker
echo "🔧 Configurando Jenkins em container Docker..."
docker volume create jenkins_home >/dev/null || true

docker rm -f jenkins >/dev/null 2>&1 || true
docker volume rm jenkins_home >/dev/null 2>&1 || true
docker volume create jenkins_home >/dev/null || true

# Adicionar usuário jenkins ao grupo docker do host
DOCKER_GID=$(getent group docker | cut -d: -f3)

# Criar container Jenkins
docker run -d \
  --name jenkins \
  --restart=unless-stopped \
  -p 8080:8080 -p 50000:50000 \
  -v jenkins_home:/var/jenkins_home \
  -v /var/run/docker.sock:/var/run/docker.sock \
  --group-add "$DOCKER_GID" \
  -e MINIKUBE_IP="${MINIKUBE_IP}" \
  jenkins/jenkins:2.440.3-jdk17

# Aguardar container iniciar
echo "⏳ Aguardando Jenkins iniciar (30s)..."
sleep 30

# Instalar Docker CLI no container
echo "🔧 Instalando Docker CLI no container Jenkins..."
docker exec -u 0 jenkins apt-get update
docker exec -u 0 jenkins apt-get install -y ca-certificates curl
docker exec -u 0 jenkins install -m 0755 -d /etc/apt/keyrings
docker exec -u 0 jenkins curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
docker exec -u 0 jenkins chmod a+r /etc/apt/keyrings/docker.asc
docker exec -u 0 jenkins sh -c 'echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian $(. /etc/os-release && echo "$VERSION_CODENAME") stable" > /etc/apt/sources.list.d/docker.list'
docker exec -u 0 jenkins apt-get update
docker exec -u 0 jenkins apt-get install -y docker-ce-cli

# Reiniciar Jenkins para aplicar alterações
echo "🔄 Reiniciando Jenkins..."
docker restart jenkins
sleep 15

echo "✅ Instalação concluída!"
echo "Acesse Jenkins: http://localhost:8080"
echo "Para obter a senha inicial do Jenkins, execute:"
echo "docker exec jenkins cat /var/jenkins_home/secrets/initialAdminPassword"
echo "Aguarde alguns segundos após a inicialização para o arquivo da senha ser criado."

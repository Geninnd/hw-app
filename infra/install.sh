#!/usr/bin/env bash
set -euo pipefail

echo "🐳 Redefinindo contexto Docker para o daemon do host..."
eval $(minikube docker-env -u) || true

echo "🚀 Iniciando instalação das ferramentas necessárias..."

# Função para checar existência de comando
command_exists() { command -v "$1" >/dev/null 2>&1; }

echo "📦 Atualizando repositórios e instalando pacotes básicos..."
sudo apt update
sudo apt install -y git docker.io curl unzip jq

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

# Parar e remover Minikube existente para um início limpo
echo "🧹 Limpando instalação anterior do Minikube..."
minikube stop >/dev/null 2>&1 || true
minikube delete --all --purge >/dev/null 2>&1 || true

# --- ETAPA 1: INICIAR MINIKUBE E CONFIGURAR DOCKER ---

echo "🚀 Iniciando Minikube com a configuração base..."
minikube start \
  --driver=docker \
  --kubernetes-version=v1.26.3

echo "🔗 Obtendo IP real do Minikube..."
MINIKUBE_IP=$(minikube ip)
echo "    -> IP do Minikube: ${MINIKUBE_IP}"

echo "🔐 Configurando o Docker do host para confiar no registro do Minikube..."
DAEMON_JSON="/etc/docker/daemon.json"
REGISTRY_ADDR="${MINIKUBE_IP}:5000"

if ! sudo test -f "${DAEMON_JSON}"; then echo "{}" | sudo tee "${DAEMON_JSON}" > /dev/null; fi
ORIGINAL_CONFIG=$(sudo cat "${DAEMON_JSON}")
MODIFIED_CONFIG=$(echo "${ORIGINAL_CONFIG}" | sudo jq --arg addr "${REGISTRY_ADDR}" '."insecure-registries" = (."insecure-registries" // [] | . + [$addr] | unique)')

if [ "${ORIGINAL_CONFIG}" != "${MODIFIED_CONFIG}" ]; then
  echo "    -> Adicionando '${REGISTRY_ADDR}' a ${DAEMON_JSON}..."
  echo "${MODIFIED_CONFIG}" | sudo tee "${DAEMON_JSON}" > /dev/null
  echo "🔄 Reiniciando o Docker para aplicar as alterações..."
  sudo systemctl restart docker
  echo "    -> Docker reiniciado."
else
  echo "    -> O Docker do host já está configurado corretamente."
fi

# --- ETAPA 2: REATIVAR MINIKUBE E FINALIZAR A CONFIGURAÇÃO ---

echo "🚀 Reativando e finalizando a configuração do Minikube..."
minikube start \
  --driver=docker \
  --kubernetes-version=v1.26.3 \
  --memory=4096 \
  --cpus=2 \
  --addons=storage-provisioner \
  --addons=default-storageclass \
  --insecure-registry="localhost:5000"

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

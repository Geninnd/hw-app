# Hello World App

Este repositório contém uma aplicação Hello World com pipeline CI/CD utilizando GitOps.

## Pré-requisitos

- Sistema operacional Linux (Ubuntu/Debian)
- Acesso sudo
- Conta no GitHub

## 1. Fork dos Repositórios

1. Faça fork dos repositórios:
   - Este repositório (`hw-app`)
   - Repositório de manifestos (`hw-k8s`)

2. Clone seus forks localmente:
   ```bash
   git clone https://github.com/SEU_USUARIO/hw-app.git
   git clone https://github.com/SEU_USUARIO/hw-k8s.git
   ```

## 2. Instalação das Ferramentas

Execute o script de instalação:
```bash
cd hw-app
chmod +x infra/install.sh
./infra/install.sh
```

O script instalará:
- Docker e Registry local
- kubectl e Minikube
- Jenkins (instalação local)
- ArgoCD

## 3. Configuração do Jenkins

1. Inicie o Jenkins via Docker:
   ```bash
   docker volume create jenkins-data
   docker run --name jenkins-server --restart=unless-stopped -d \
     -p 8080:8080 -p 50000:50000 \
     -v jenkins-data:/var/jenkins_home \
     -v /var/run/docker.sock:/var/run/docker.sock \
     -v $(which docker):/usr/bin/docker \
     jenkins/jenkins:lts-jdk17
   ```

2. Obtenha a senha inicial:
   ```bash
   docker exec jenkins-server cat /var/jenkins_home/secrets/initialAdminPassword
   ```

3. Acesse Jenkins em [http://localhost:8080](http://localhost:8080)

4. Instale os plugins necessários:
   - Git plugin
   - Pipeline
   - Docker Pipeline
   - Credentials Binding
   - GitHub Integration

5. Configure as credenciais (Manage Jenkins → Credentials → System → Global):
   - Adicione "Username with password":
     - ID: `github-credentials`
     - Description: GitHub Credentials
     - Username: seu usuário do GitHub
     - Password: seu Personal Access Token
   
   - Adicione "Secret text":
     - ID: `manifests-repo-url`
     - Description: Manifests Repository URL
     - Secret: URL do seu fork do hw-k8s (sem https://)

6. Crie o pipeline:
   - Novo Item → Pipeline
   - Nome: `hw-app`
   - Pipeline from SCM
   - URL: URL do seu fork do hw-app
   - Credentials: selecione github-credentials
   - Branch: */main
   - Path: infra/Jenkinsfile

## 4. Configuração do Kubernetes

```bash
# Configurar acesso ao registry local
echo "127.0.0.1 host.minikube.internal" | sudo tee -a /etc/hosts
```

## 5. Configuração do ArgoCD

1. Obter senha e acessar:
   ```bash
   kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
   kubectl port-forward svc/argocd-server -n argocd 8443:443
   ```
   Acesse: https://localhost:8443 (usuário: admin)

2. Configurar aplicação:
   - NEW APP
   - Nome: `hw-app`
   - Projeto: `default`
   - Repositório: URL do seu fork do hw-k8s
   - Path: `manifests`
   - Cluster: `https://kubernetes.default.svc`
   - Namespace: `hw-app`
   - AUTO-SYNC: Enabled

## 6. Teste do Pipeline

1. Faça uma alteração:
   ```bash
   cd hw-app
   # Edite src/main.py
   git commit -am "test: teste do pipeline"
   git push
   ```

2. Acompanhe:
   - Jenkins: http://localhost:8080
   - ArgoCD: https://localhost:8443

## Troubleshooting

1. **Jenkins não inicia**:
   ```bash
   sudo systemctl status jenkins
   sudo tail -f /var/log/jenkins/jenkins.log
   ```

2. **Pods não iniciam**:
   ```bash
   kubectl describe pod <pod-name> -n hw-app
   ```

3. **ArgoCD não sincroniza**:
   ```bash
   argocd app get hw-app
   argocd app sync hw-app
   ```

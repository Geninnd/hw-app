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
- Docker
- kubectl e Minikube
- Jenkins (instalação local)
- ArgoCD

## 3. Gerando o Token do GitHub (Personal Access Token)

Para que o Jenkins acesse seus repositórios privados ou faça push nos manifestos, é necessário um token do GitHub:

1. Acesse: [https://github.com/settings/tokens](https://github.com/settings/tokens)
2. Clique em "Generate new token" (Classic).
3. Dê um nome (ex: `jenkins-token`), selecione a validade e marque os escopos:
   - `repo` (acesso total aos repositórios)
   - `workflow` (opcional, para GitHub Actions)
4. Gere o token e **salve em local seguro** (você verá o token apenas uma vez).
5. Use esse token ao configurar as credenciais no Jenkins.

## 4. Iniciando o registro Docker dentro do Minikube

> **Importante:** O registro Docker deve rodar dentro do Minikube para que o cluster Kubernetes consiga acessar as imagens via `localhost:5000`.

1. Inicie o Minikube com suporte a registro inseguro:
   ```bash
   minikube stop
   minikube start --insecure-registry="localhost:5000"
   ```

2. Inicie o registro dentro do Minikube:
   ```bash
   minikube ssh -- "docker run -d -p 5000:5000 --restart=always --name registry registry:2"
   ```

3. Verifique se o registro está rodando:
   ```bash
   minikube ssh "curl -s http://localhost:5000/v2/_catalog"
   # Deve retornar: {"repositories":[]}
   ```

## 5. Build e push das imagens para o registro do Minikube

Antes de buildar e dar push, direcione o Docker do seu terminal para o ambiente do Minikube:

```bash
eval $(minikube docker-env)
```

Agora, faça o build e o push da imagem:

```bash
cd hw-app
# Use o comando dentro da pasta hw-app
# Exemplo para tag 14:
docker build -t localhost:5000/hw-app:14 -f infra/Dockerfile .
docker push localhost:5000/hw-app:14
```

> **Atenção:** O contexto do build (`.`) deve conter a pasta `src/` e o Dockerfile deve ser referenciado corretamente.

## 6. Configuração do Jenkins

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

## 7. Configuração do Kubernetes

> **Não é mais necessário rodar registry local no host!**

## 8. Configuração do ArgoCD

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

## 9. Configurando Webhook do GitHub com ngrok (para testes locais)

Para que o Jenkins seja notificado automaticamente a cada push no GitHub, configure um webhook usando o ngrok:

1. **Instale o ngrok:**
   - Acesse o site oficial: [https://ngrok.com/](https://ngrok.com/)
   - Siga as instruções de instalação e crie uma conta gratuita.

2. **Inicie o ngrok para expor o Jenkins:**
   ```bash
   ngrok http 8080
   ```
   - O ngrok irá gerar uma URL pública (ex: `https://xxxxxx.ngrok.io`).

3. **Configure o webhook no GitHub:**
   - No repositório do seu fork do `hw-app`, acesse **Settings > Webhooks > Add webhook**.
   - Em **Payload URL**, coloque: `https://xxxxxx.ngrok.io/github-webhook/` (ajuste conforme a URL do ngrok e o endpoint do Jenkins).
   - Content type: `application/json`
   - Escolha: Just the push event
   - Salve o webhook.

4. **Teste:**
   - Faça um push no repositório e verifique se o Jenkins dispara o build automaticamente.

## 10. Teste do Pipeline

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

1. **Pods não iniciam (ImagePullBackOff):**
   - Verifique se a imagem foi enviada para o registro dentro do Minikube:
     ```bash
     minikube ssh "curl -s http://localhost:5000/v2/_catalog"
     ```
   - Certifique-se de que o manifest do deployment está usando a tag correta:
     ```yaml
     image: localhost:5000/hw-app:<TAG>
     ```
   - Se necessário, force o redeploy:
     ```bash
     kubectl rollout restart deployment hw-app -n hw-app
     ```

2. **Jenkins não faz push para o registro:**
   - Certifique-se de que o Jenkins está rodando com acesso ao Docker do host.
   - Se for build manual, sempre use `eval $(minikube docker-env)` antes do build/push.

3. **ArgoCD não sincroniza:**
   ```bash
   argocd app get hw-app
   argocd app sync hw-app
   ```

## Fluxo correto para rodar a aplicação

1. Inicie o Minikube com o registro inseguro.
2. Suba o registro Docker dentro do Minikube.
3. Direcione o Docker do terminal para o ambiente do Minikube.
4. Build e push da imagem para `localhost:5000`.
5. Garanta que o manifest do deployment usa `localhost:5000/hw-app:<TAG>`.
6. Sincronize pelo ArgoCD.
7. Pronto! O pod deve subir sem erros.

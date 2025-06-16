# Hello World App

Este repositório contém uma aplicação "Hello World" com uma pipeline de CI/CD utilizando Jenkins, ArgoCD e GitOps.

## Pré-requisitos

- Sistema operacional baseado em Linux (testado em Ubuntu/Debian).
- Acesso `sudo` para instalação de pacotes.
- Uma conta no GitHub.

## 1. Preparação dos Repositórios

Antes de começar, você precisa ter sua própria cópia dos repositórios.

1.  **Faça um Fork** de ambos os repositórios para a sua conta do GitHub:
    *   Repositório da Aplicação: `hw-app`
    *   Repositório de Manifestos Kubernetes: `hw-k8s`

2.  **Clone o seu fork** da aplicação (`hw-app`) para a sua máquina local:
    ```bash
    git clone https://github.com/SEU_USUARIO/hw-app.git
    cd hw-app
    ```
    Substitua `SEU_USUARIO` pelo seu nome de usuário do GitHub.

## 2. Instalação e Configuração do Ambiente

O ambiente de desenvolvimento (Minikube, Jenkins, ArgoCD, etc.) é configurado automaticamente por um único script.

- **Execute o script de instalação:**
  ```bash
  chmod +x infra/install.sh
  ./infra/install.sh
  ```
  Este comando irá baixar e configurar todas as ferramentas necessárias. O processo pode levar alguns minutos.

## 3. Configuração do Jenkins

Após a instalação, você precisa configurar o Jenkins para que ele possa se comunicar com seus repositórios no GitHub.

### 3.1. Crie um Personal Access Token (PAT) no GitHub

1.  Acesse a página de tokens do GitHub: [github.com/settings/tokens](https://github.com/settings/tokens).
2.  Clique em **Generate new token** e selecione **Generate new token (classic)**.
3.  Dê um nome para o token (ex: `jenkins-token`).
4.  Selecione a data de expiração.
5.  Marque o escopo **`repo`** (acesso total aos repositórios).
6.  Clique em **Generate token** e **guarde o token em um local seguro**. Você não poderá vê-lo novamente.

### 3.2. Configure as Credenciais no Jenkins

1.  **Acesse o Jenkins**: Abra [http://localhost:8080](http://localhost:8080) no seu navegador.

2.  **Obtenha a senha inicial**: O script de instalação exibe a senha no final. Se precisar, execute o comando abaixo em seu terminal:
    ```bash
    docker exec jenkins cat /var/jenkins_home/secrets/initialAdminPassword
    ```

3.  **Configure as credenciais necessárias**:
    - Vá para **Manage Jenkins → Credentials → System → Global credentials (unrestricted)**.
    - Clique em **Add Credentials**.

    - **Credencial 1: GitHub (Usuário e Token)**
      - **Kind**: `Username with password`
      - **ID**: `github-credentials`
      - **Description**: `Credenciais de acesso ao GitHub`
      - **Username**: Seu nome de usuário do GitHub.
      - **Password**: O Personal Access Token que você acabou de criar.

    - **Credencial 2: URL do Repositório de Manifestos**
      - **Kind**: `Secret text`
      - **ID**: `manifests-repo-url`
      - **Description**: `URL do repositório de manifestos`
      - **Secret**: A URL do seu fork do `hw-k8s`, **sem** o `https://`.
        - Exemplo: `github.com/SEU_USUARIO/hw-k8s.git`

### 3.3. Crie o Pipeline

1.  Na página inicial do Jenkins, clique em **New Item**.
2.  Dê um nome ao pipeline (ex: `hw-app`) e selecione **Pipeline**. Clique em **OK**.
3.  Na aba **Pipeline**, defina as seguintes configurações:
    - **Definition**: `Pipeline script from SCM`
    - **SCM**: `Git`
    - **Repository URL**: A URL do seu fork do `hw-app`.
      - Exemplo: `https://github.com/SEU_USUARIO/hw-app.git`
    - **Credentials**: Selecione `github-credentials`.
    - **Branch Specifier**: `*/main`
    - **Script Path**: `infra/Jenkinsfile`
4.  Salve o pipeline.

## 4. Configuração do ArgoCD

Acesse a interface do ArgoCD e configure-o para observar seu repositório de manifestos.

1.  **Obtenha a senha do ArgoCD**:
    ```bash
    kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
    ```

2.  **Acesse a interface**: Encaminhe a porta do ArgoCD para o seu `localhost`.
    ```bash
    kubectl port-forward svc/argocd-server -n argocd 8443:443
    ```
    Acesse [https://localhost:8443](https://localhost:8443) (usuário: `admin`, senha: a que você obteve acima).

3.  **Crie a aplicação**:
    - Clique em **NEW APP**.
    - **Application Name**: `hw-app`
    - **Project**: `default`
    - **Repository URL**: A URL do seu fork do `hw-k8s`.
    - **Path**: `manifests`
    - **Destination Cluster**: `https://kubernetes.default.svc`
    - **Destination Namespace**: `hw-app` (será criado se não existir)
    - **Sync Policy**: `Automatic` com a opção `Prune Resources` marcada.

## 5. Teste o Fluxo Completo

Agora, tudo está pronto. Para testar o pipeline:

1.  Faça uma alteração em qualquer arquivo no seu repositório `hw-app` local.
    ```bash
    # Exemplo: editando o arquivo principal da aplicação
    # nano src/main.py
    ```

2.  Faça o commit e o push das alterações:
    ```bash
    git add .
    git commit -m "feat: Testando a pipeline de CI/CD"
    git push origin main
    ```

O push irá disparar a pipeline no Jenkins, que irá construir a nova imagem, publicá-la no registro local e atualizar o repositório de manifestos. Em seguida, o ArgoCD detectará a mudança e fará o deploy da nova versão no cluster Kubernetes.

## 6. Acessando a Aplicação

Depois que o ArgoCD sincronizar a aplicação, você pode acessá-la diretamente no seu navegador.

- **Execute o seguinte comando** em seu terminal:
  ```bash
  minikube service hw-app -n hw-app
  ```
Este comando cria um túnel de acesso ao serviço da aplicação e abre automaticamente a URL no seu navegador padrão. Obs: nao feche o terminal.

## 7. Troubleshooting

- **Erro `ImagePullBackOff` no Kubernetes**:
  - **Causa Comum**: O cluster não consegue encontrar a imagem.
  - **Verificação**: Certifique-se de que o registro Docker está rodando dentro do Minikube. A pipeline do Jenkins é responsável por atualizar o `deployment.yaml` com o endereço IP correto do registro e a tag da imagem.
  - **Comando útil**: `kubectl describe pod <NOME_DO_POD> -n hw-app` para ver mais detalhes do erro.

- **Build falhando no Jenkins**:
  - Verifique os logs da build no Jenkins para identificar o estágio que falhou.
  - Certifique-se de que todas as credenciais foram criadas com os **IDs corretos**.

- **ArgoCD não sincroniza**:
  - Acesse a interface do ArgoCD e verifique o status da aplicação `hw-app`.
  - Use o botão **Refresh** para forçar a verificação do repositório Git e o botão **Sync** para aplicar as mudanças manualmente se necessário.

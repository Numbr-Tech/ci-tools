# Deployer votre application avec ci-tools

1. Dupliquer le tciket https://manakin.atlassian.net/browse/NT-31 et mettre à jour les informations. Informerles devops (Gregory CADICI)

2. Créer un fichier Infra/containerapp.yaml.tpl

    ```yaml
    name: __PROJECT_NAME__
    type: Microsoft.App/containerApps
    location: __AZURE_LOCATION__
    identity:
      type: UserAssigned
      userAssignedIdentities:
        __AZURE_SHARED_IDENTITY__: {}
    properties:
      environmentId: __AZURE_ENVIRONMENT_ID__
      configuration:
        secrets:
          - name: my-secret
            identity: "__AZURE_SHARED_IDENTITY__"
            keyVaultUrl: "__AZURE_VAULT_BASE_URL__/my-secret"
        ingress:
          allowInsecure: false
          external: __INGRESS_EXTERNAL__
          targetPort: __INGRESS_PORT__
        registries:
          - server: __AZURE_REGISTRY_FQDN__
            identity: __AZURE_SHARED_IDENTITY__
    template:
      containers:
        - image: __IMAGE_PATH__
          name: __PROJECT_NAME__
          resources:
            cpu: "__RESOURCE_CPU__"
            memory: "__RESOURCE_MEMORY__"
          env:
            - name: "INFRA_ENV"
              value: "__INFRA_ENV__"
      scale:
        minReplicas: __SCALE_MIN_REPLICAS__
        maxReplicas: __SCALE_MAX_REPLICAS__
        rules:
          - name: "http-scaler"
            http:
              metadata:
                concurrentRequests: "__SCALE_CONCURRENT_REQUESTS__"
    ```

3. Créer un fichier Dockerfile avec les instructions permettant de build votre container

4. Ajouter dans votre projet un fichier .github/workflows/deploy.yml. 2 options s'offrent à vous

    a. Déployer de manière indépendante votre application via github workflow

      ```yaml
      name: Deploy

      on:
          push:
              branches:
                  - staging
                  - main
          workflow_dispatch:

      permissions:
          id-token: write
          contents: read

      jobs:
          deploy:
              uses: Numbr-Tech/ci-tools/.github/workflows/_templates-deploy-simple.yml@v1
              with:
                  PROJECT_NAME: le-nom-de-votre-projet
                  # vous pouvez surcharger les valeurs par défaut des paramètres définis ici https://github.com/Numbr-Tech/ci-tools/blob/main/.github/workflows/_templates-deploy-simple.yml
              secrets: inherit
      ```

    b. Déployer avec docker factory votre application via github workflow

      ```yaml
      name: Deploy

      on:
          push:
              branches:
              - feat/deploy-container-app
              - main
          workflow_dispatch:

      permissions:
          id-token: write
          contents: read

      jobs:
          trigger-docker-factory-ci:
              uses: Numbr-Tech/ci-tools/.github/workflows/_templates-trigger-docker-factory-ci.yml@v1
              with:
                  DOCKER_FACTORY_BRANCH_NAME: 'feat/dash'
                  PROJECT_NAME: 'cubber-dash'
              secrets: inherit

          create-environment:
              uses: Numbr-Tech/ci-tools/.github/workflows/_templates-create-environment.yml@v1
              needs: [trigger-docker-factory-ci]
              with:
                  PROJECT_NAME: 'cubber-dash'
              secrets: inherit

          deploy:
              uses: Numbr-Tech/ci-tools/.github/workflows/_templates-deploy.yml@v1
              needs: [create-environment]
              with:
                  PROJECT_NAME: 'cubber-dash'
              secrets: inherit
      ```

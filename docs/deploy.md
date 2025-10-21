# Deployer votre application avec ci-tools

1. Dupliquer le ticket https://manakin.atlassian.net/browse/NT-31 et mettre à jour les informations. Informerles devops (Gregory CADICI)

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
        - image: __PHP.IMAGE_PATH__
          name: php
          resources:
            cpu: "__PHP.RESOURCE_CPU__"
            memory: "__PHP.RESOURCE_MEMORY__"
          env:
            - name: "INFRA_ENV"
              value: "__INFRA_ENV__"
            - name: MY_SECRET
              secretRef: my-secret
        - image: __NGINX.IMAGE_PATH__
          name: nginx
          resources:
            cpu: "__NGINX.RESOURCE_CPU__"
            memory: "__NGINX.RESOURCE_MEMORY__"
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

3. Créer vos component. Dans cette exemple PHP et NGINX.
   
   a. créer un fichier Dockerfile par component (nginx, php, ...) avec les instructions permettant de build votre container. Ex: Dockerfile-nginx.

   b. créer votre config par environement en créant un fichier par env dans Infra. Ex: staging.yaml.
      ```yaml
      autoscaling:
        min: '3'
        max: '10'
        concurrent_requests: '30'
      components:
        nginx:
          resources:
            cpu: '0.1'
            memory: '0.1Gi'
        php:
          resources:
            cpu: '0.5'
            memory: '1.0Gi'
      ```

4. Ajouter dans votre projet un fichier .github/workflows/deploy.yml.

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


#!/bin/bash

set -e

show_help() {
    echo "Usage: $0 [OPTIONS] [environment] [output_file]"
    echo ""
    echo "Options:"
    echo "  --env              Spécifier l'environnement"
    echo "  --container-app-environment-name Spécifier le nom de l'environnement Container App"
    echo "  --registry-fqdn    Spécifier le FQDN du registre Azure"
    echo "  --subscription-id  Spécifier l'ID de la subscription Azure"
    echo "  --resource-group   Spécifier le nom du groupe de ressources"
    echo "  --image-tag        Spécifier le tag de l'image Docker (défaut: latest)"
    echo "  --version          Spécifier la version (défaut: image-tag)"
    echo "  --values-file      Spécifier le chemin du fichier de value (défaut: ./Infra/values.yaml)"
    echo "  --output-file      Spécifier le chemin du fichier yaml de sortie (défaut: ./Infra/containerapp.yaml)"
    echo "  --debug            Activer le mode debug"
    echo "  -h, --help         Afficher cette aide"
    echo ""
    echo "Exemples:"
    echo "  $0 --registry-fqdn myreg.azurecr.io --env staging --container-app-environment-name giwb-api-staging --image-tag v1.2.3 --image-tag latest --version v2.0.0 --debug"
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --env)
            ENVIRONMENT="$2"
            shift 2
            ;;
        --subscription-id)
            AZURE_SUBSCRIPTION_ID="$2"
            shift 2
            ;;
        --container-app-environment-name)
            AZURE_CONTAINERAPP_ENVIRONMENT_NAME="$2"
            shift 2
            ;;
        --registry-fqdn)
            AZURE_REGISTRY_FQDN="$2"
            shift 2
            ;;
        --resource-group)
            AZURE_RESOURCE_GROUP_NAME="$2"
            shift 2
            ;;
        --version)
            VERSION="$2"
            shift 2
            ;;
        --image-tag)
            IMAGE_TAG="$2"
            shift 2
            ;;
        --output-file)
            OUTPUT_FILE="$2"
            shift 2
            ;;
        --values-file)
            VALUES_FILE="$2"
            shift 2
            ;;
        --debug)
            DEBUG="true"
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        -*)
            echo "Option inconnue: $1"
            show_help
            exit 1
            ;;
    esac
done

if [ -z "$AZURE_SUBSCRIPTION_ID" ]; then
    echo "Erreur: L'ID de la subscription Azure n'est pas spécifié"
    show_help
    exit 1
fi

if [ -z "$AZURE_REGISTRY_FQDN" ]; then
    echo "Erreur: Le FQDN du registre Azure n'est pas spécifié"
    show_help
    exit 1
fi

if [ -z "$AZURE_RESOURCE_GROUP_NAME" ]; then
    echo "Erreur: Le nom du groupe de ressources n'est pas spécifié"
    show_help
    exit 1
fi

if [ -z "$AZURE_CONTAINERAPP_ENVIRONMENT_NAME" ]; then
    echo "Erreur: Le nom de l'environnement Container App n'est pas spécifié"
    show_help
    exit 1
fi

VALUES_FILE=${VALUES_FILE:-"./Infra/values.yaml"}
OUTPUT_FILE=${OUTPUT_FILE:-"./Infra/containerapp.yaml"}

if [ -f "$OUTPUT_FILE" ]; then
    echo "Le fichier $OUTPUT_FILE existe déjà. Pas de génération nécessaire."
    exit 0
fi

# Vérifications
if [[ ! -f "$VALUES_FILE" ]]; then
    echo "Erreur: Le fichier $VALUES_FILE n'existe pas"
    exit 1
fi

if ! command -v yq &> /dev/null; then
    echo "Erreur: yq n'est pas installé. Installez-le avec: brew install yq"
    exit 1
fi

# Extraire les valeurs depuis values.yaml
PROJECT_NAME=$(yq ".project" "$VALUES_FILE")
APPLI_NAME=$(yq ".appli" "$VALUES_FILE")
FULL_NAME=${ENVIRONMENT}-${PROJECT_NAME}-${APPLI_NAME}
LOCATION=$(yq ".location // \"francecentral\"" "$VALUES_FILE")
SHARED_IDENTITY_ID=$(yq ".identity.url // \"/subscriptions/${AZURE_SUBSCRIPTION_ID}/resourceGroups/rg-frc-pprodgeneral/providers/Microsoft.ManagedIdentity/userAssignedIdentities/mid-frc-iac\"" "$VALUES_FILE" | xargs)
ENVIRONMENT_ID=$(yq ".environment.id // \"/subscriptions/${AZURE_SUBSCRIPTION_ID}/resourceGroups/${AZURE_RESOURCE_GROUP_NAME}/providers/Microsoft.App/managedEnvironments/${AZURE_CONTAINERAPP_ENVIRONMENT_NAME}\"" "$VALUES_FILE" | xargs)
INGRESS_EXTERNAL=$(yq '.ingress.external // true' "$VALUES_FILE")
INGRESS_PORT=$(yq '.ingress.port // 80' "$VALUES_FILE")
VAULT_NAME=$(yq ".vault.name // \"key-frc-${PROJECT_NAME}\"" "$VALUES_FILE")
VAULT_BASE_URL=$(yq ".vault.base_url // \"https://${VAULT_NAME}.vault.azure.net/secrets\"" "$VALUES_FILE")

SCALE_MIN=$(yq eval ".env.$ENVIRONMENT.autoscaling.min // 1" "$VALUES_FILE")
SCALE_MAX=$(yq eval ".env.$ENVIRONMENT.autoscaling.max // 1" "$VALUES_FILE")
SCALE_CONCURRENT=$(yq eval ".env.$ENVIRONMENT.autoscaling.concurrent_requests // 10" "$VALUES_FILE")

if [ "${DEBUG}" = "true" ]; then
    echo "PROJECT_NAME: $PROJECT_NAME"
    echo "APPLI_NAME: $APPLI_NAME"
    echo "LOCATION: $LOCATION"
    echo "SHARED_IDENTITY_ID: $SHARED_IDENTITY_ID"
    echo "ENVIRONMENT_ID: $ENVIRONMENT_ID"
    echo "INGRESS_EXTERNAL: $INGRESS_EXTERNAL"
    echo "INGRESS_PORT: $INGRESS_PORT"
    echo "VAULT_NAME: $VAULT_NAME"
    echo "VAULT_BASE_URL: $VAULT_BASE_URL"
    echo "AZURE_REGISTRY_FQDN: $AZURE_REGISTRY_FQDN"
    echo "SCALE_MIN: $SCALE_MIN"
    echo "SCALE_MAX: $SCALE_MAX"
    echo "SCALE_CONCURRENT: $SCALE_CONCURRENT"
fi

# Créer le fichier de base
cat > "$OUTPUT_FILE" << EOF
name: $FULL_NAME
type: Microsoft.App/containerApps
location: $LOCATION
identity:
  type: UserAssigned
  userAssignedIdentities:
    "$SHARED_IDENTITY_ID": {}
properties:
  environmentId: $ENVIRONMENT_ID
  configuration:
    extensions:
      azureMonitor:
        enabled: true
    ingress:
      allowInsecure: false
      external: $INGRESS_EXTERNAL
      targetPort: $INGRESS_PORT
    registries:
      - server: $AZURE_REGISTRY_FQDN
        identity: $SHARED_IDENTITY_ID
template:
  scale:
    minReplicas: $SCALE_MIN
    maxReplicas: $SCALE_MAX
    rules:
      - name: "http-scaler"
        http:
          metadata:
            concurrentRequests: "$SCALE_CONCURRENT"
EOF

# Créer les secrets
echo "secrets:" > /tmp/secrets.yaml
yq eval '.envVariables[] | select(.secretRef != null) | .secretRef' "$VALUES_FILE" | sort -u | while read -r secret_ref; do
    cat >> /tmp/secrets.yaml << EOF
  - name: "$secret_ref"
    identity: "$SHARED_IDENTITY_ID"
    keyVaultUrl: "$VAULT_BASE_URL/$FULL_NAME-$secret_ref"
EOF
done

# Injecter les secrets
yq eval --inplace 'load("/tmp/secrets.yaml") as $secrets | .properties.configuration.secrets = $secrets.secrets' "$OUTPUT_FILE"

# Créer les conteneurs
yq eval --null-input '.containers = []' > /tmp/containers.yaml
yq eval ".env.$ENVIRONMENT.components | to_entries | .[] | .key" "$VALUES_FILE" | while read -r component_name; do
    cpu=$(yq eval ".env.$ENVIRONMENT.components.$component_name.resources.cpu" "$VALUES_FILE")
    memory=$(yq eval ".env.$ENVIRONMENT.components.$component_name.resources.memory" "$VALUES_FILE")

    if [ -z "$IMAGE_TAG" ]; then
      IMAGE_TAG=$(shasum "Dockerfile-$component_name" | awk '{print $1}')
    fi

    yq eval --inplace ".containers += [{
        \"image\": \"$AZURE_REGISTRY_FQDN/$FULL_NAME-$component_name:$IMAGE_TAG\",
        \"name\": \"$FULL_NAME-$component_name\",
        \"resources\": {
            \"cpu\": \"$cpu\",
            \"memory\": \"$memory\"
        }
    }]" /tmp/containers.yaml
done

# Injecter les conteneurs
yq eval --inplace 'load("/tmp/containers.yaml") as $containers | .template.containers = $containers.containers' "$OUTPUT_FILE"

# Créer les variables d'environnement
yq eval --null-input '.env = []' > /tmp/env.yaml
yq eval '.envVariables[] | select(.value != null) | "- name: " + .name + "\n  value: " + .value' "$VALUES_FILE" | while IFS= read -r line; do
    if [[ "$line" == "- name:"* ]]; then
        name=$(echo "$line" | sed 's/- name: //')
        read -r next_line
        if [[ "$next_line" == "value:"* ]]; then
            value=$(echo "$next_line" | sed 's/value: //')
            yq eval --inplace '.env += [{"name": "'"$name"'", "value": "'"$value"'"}]' /tmp/env.yaml
        fi
    fi
done

yq eval '.envVariables[] | select(.secretRef != null) | "- name: " + .name + "\n  secretRef: " + .secretRef' "$VALUES_FILE" | while IFS= read -r line; do
    if [[ "$line" == "- name:"* ]]; then
        name=$(echo "$line" | sed 's/- name: //')
        read -r next_line
        if [[ "$next_line" == "secretRef:"* ]]; then
            secret_ref=$(echo "$next_line" | sed 's/secretRef: //')
            yq eval --inplace '.env += [{"name": "'"$name"'", "secretRef": "'"$secret_ref"'"}]' /tmp/env.yaml
        fi
    fi
done

# Ajouter des variables d'environnement
yq eval --inplace '.env += [{"name": "INFRA_ENV", "value": "'"$ENVIRONMENT"'"}]' /tmp/env.yaml
yq eval --inplace '.env += [{"name": "VERSION", "value": "'"$VERSION"'"}]' /tmp/env.yaml

# Injecter les variables d'environnement
yq eval --inplace 'load("/tmp/env.yaml") as $env | .template.containers[].env = $env.env' "$OUTPUT_FILE"

# Nettoyer
rm -f /tmp/secrets.yaml /tmp/containers.yaml /tmp/env.yaml

if [ "${DEBUG}" = "true" ]; then
    echo "Output file: $OUTPUT_FILE"
    cat "$OUTPUT_FILE"
fi
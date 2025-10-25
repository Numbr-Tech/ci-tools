#!/bin/bash

set -e

show_help() {
    echo "Usage: $0 [OPTIONS] [environment] [output_file]"
    echo ""
    echo "Options:"
    echo "  --env              Spécifier l'environnement"
    echo "  --subscription-id  Spécifier l'ID de la subscription Azure"
    echo "  --image-tag        Spécifier le tag de l'image Docker (défaut: latest)"
    echo "  --version          Spécifier la version (défaut: image-tag)"
    echo "  --debug            Activer le mode debug"
    echo "  -h, --help         Afficher cette aide"
    echo ""
    echo "Exemples:"
    echo "  $0 --env staging --image-tag v1.2.3 --image-tag latest --version v2.0.0 --debug"
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
        --version)
            VERSION="$2"
            shift 2
            ;;
        --image-tag)
            IMAGE_TAG="$2"
            shift 2
            ;;
        --debug)
            DEBUG="true"
            shift
            ;;
        --dry-run)
            DRY_RUN="true"
            shift
            ;;    
        -h|--help)
            show_help
            exit 0
            ;;
        -*)
            echo -e "${RED}❌ Option inconnue: $1${NC}"
            show_help
            exit 1
            ;;
    esac
done

if [ -z "$VERSION" ]; then
    VERSION=$IMAGE_TAG
fi

if [ -z "$AZURE_SUBSCRIPTION_ID" ]; then
    echo -e "${RED}❌ Erreur: L'ID de la subscription Azure n'est pas spécifié${NC}"
    show_help
    exit 1
fi

if [ -z "$ENVIRONMENT" ]; then
    echo -e "${RED}❌ Erreur: L'env n'est pas spécifié${NC}"
    show_help
    exit 1
fi

DIR=$(dirname "${BASH_SOURCE[0]}")
VALUES_FILE="./Infra/values.yaml"
YAML_CONFIG_PATH='./Infra/containerapp.yaml'
PROJECT_NAME=$(yq '.project' "${VALUES_FILE}")
APPLI_NAME=$(yq '.appli' "${VALUES_FILE}")
AZURE_REGISTRY_FQDN=$([ "$ENVIRONMENT" = "production" ] && echo "nbtreg.azurecr.io" || echo "pprodnbtregistry-aucgecdkece6b5d7.azurecr.io")
AZURE_CONTAINERAPP_ENVIRONMENT_NAME=${ENVIRONMENT}-${PROJECT_NAME} \
AZURE_LOCATION=$(yq ".location // \"francecentral\"" "${VALUES_FILE}")
AZURE_VNET_NAME=$(yq '.vnet.name // ""' "${VALUES_FILE}")
AZURE_SUBNET_NAME=$(yq '.vnet.subnet.name // ""' "${VALUES_FILE}")

AZURE_VNET_ENABLED=$(
  if [ "$(yq '.vnet.enabled // false' "${VALUES_FILE}")" = "true" ] \
     || { [ -n "${AZURE_VNET_NAME}" ] && [ -n "${AZURE_SUBNET_NAME}" ]; }; then
    echo "true"
  else
    echo "false"
  fi
)
AZURE_CONTAINERAPP_ENVIRONMENT_INTERNAL_ONLY=$(yq '.appEnv.internalOnly // false' ${VALUES_FILE})
AZURE_RESOURCE_GROUP_NAME=$(yq ".resourceGroup.current.name // \"rg-frc-${PROJECT_NAME}\"" ${VALUES_FILE})
DOCKER_FILE_DIRECTORY='.'

# Couleurs pour la mise en forme
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
BOLD='\033[1m'
NC='\033[0m' # No Color

function run_command() {
    local CMD=("$@")
    local COMMAND_NAME="${CMD[0]}"
    local COLOR="$CYAN"
    
    # Déterminer la couleur selon le type de commande
    case "$COMMAND_NAME" in
        "docker")
            local ICON="🐳"
            ;;
        "az")
            local ICON="☁️"
            ;;
        *)
            local ICON="⚙️"
            ;;
    esac

    local WORDING="Executing"

    if [ "$DRY_RUN" = "true" ]; then
        WORDING="Would execute"
    fi

    echo -e "    ${YELLOW}🐛${NC} ${BOLD}${WORDING}:${NC} ${COLOR}${ICON} ${CMD[@]}${NC}"

    if [ "$DRY_RUN" = "true" ]; then
        return 0
    fi
    
    "${CMD[@]}"
}

function echo_title() {
    echo -e "\n\n${YELLOW}================================================================================${NC}"
    echo -e "${YELLOW}|${NC}    ${CYAN}${BOLD}$1${NC}"
    echo -e "${YELLOW}================================================================================${NC}\n"
}

#############################
# Build Container Yaml
#############################

echo_title "Building Container App Yaml $YAML_CONFIG_PATH from values file $VALUES_FILE."
DEBUG_FLAG=$([ "$DEBUG" = 'true' ] && echo '--debug' || echo '')

run_command ${DIR}/containerapp-yaml-build.sh \
  --env ${ENVIRONMENT} \
  --version ${VERSION} \
  --container-app-environment-name ${AZURE_CONTAINERAPP_ENVIRONMENT_NAME} \
  --registry-fqdn ${AZURE_REGISTRY_FQDN} \
  --resource-group ${AZURE_RESOURCE_GROUP_NAME} \
  --subscription-id ${AZURE_SUBSCRIPTION_ID} \
  --image-tag ${IMAGE_TAG} \
  --values-file ${VALUES_FILE} \
  --output-file ${YAML_CONFIG_PATH} \
  $DEBUG_FLAG


######################
# Build docker image
######################
FULL_NAME=$(yq '.name' Infra/containerapp.yaml)
CONTAINER_COUNT=$(yq '.template.containers | length' Infra/containerapp.yaml)

echo_title "Building $CONTAINER_COUNT container(s) image(s) for container app '$FULL_NAME'"

for i in $(seq 0 $((CONTAINER_COUNT - 1))); do
  NAME=$(yq ".template.containers[$i].name" $YAML_CONFIG_PATH | sed "s/${FULL_NAME}-//")
  IMAGE_PATH=$(yq ".template.containers[$i].image" $YAML_CONFIG_PATH)
  echo -e "    ${CYAN}📦${NC} ${BOLD}Building and pushing container:${NC} ${WHITE}'$NAME'${NC} ${BOLD}with image path:${NC} ${CYAN}'$IMAGE_PATH'${NC}"
  QUIET_FLAG=$([ "$DEBUG" = 'true' ] && echo '' || echo '--quiet')
  run_command docker build -t "$IMAGE_PATH" -f "$DOCKER_FILE_DIRECTORY/Dockerfile-$NAME" "$DOCKER_FILE_DIRECTORY" $QUIET_FLAG
  run_command docker push $IMAGE_PATH $QUIET_FLAG
done

############################
# CREATE CONTAINERAPP ENV
############################
if ! az containerapp env show \
  --name "${AZURE_CONTAINERAPP_ENVIRONMENT_NAME}" \
  --resource-group "${AZURE_RESOURCE_GROUP_NAME}" \
  --query "name" \
  --only-show-errors > /dev/null 2>&1
then
  VNET_OPTION=()
  if [ "${AZURE_VNET_ENABLED}" = "true" ]
  then
    AZURE_VNET_NAME="${AZURE_VNET_NAME:-vnet-frc-${ENVIRONMENT}-${PROJECT_NAME}}"
    AZURE_SUBNET_NAME="${AZURE_SUBNET_NAME:-subnet-${FULL_NAME}}"
  
    VNET_OPTION=("--infrastructure-subnet-resource-id" "/subscriptions/${AZURE_SUBSCRIPTION_ID}/resourceGroups/${AZURE_RESOURCE_GROUP_NAME}/providers/Microsoft.Network/virtualNetworks/${AZURE_VNET_NAME}/subnets/${AZURE_SUBNET_NAME}")
  fi

  echo_title "Creating Container App environment '${AZURE_CONTAINERAPP_ENVIRONMENT_NAME}'..."

  run_command az containerapp env create \
      --name "${AZURE_CONTAINERAPP_ENVIRONMENT_NAME}" \
      --resource-group "${AZURE_RESOURCE_GROUP_NAME}" \
      --location "${AZURE_LOCATION}" \
      --internal-only ${AZURE_CONTAINERAPP_ENVIRONMENT_INTERNAL_ONLY} \
      "${VNET_OPTION[@]}"
fi

############################
# CREATE CONTAINERAPP
############################
echo_title "Creating Container App '${FULL_NAME}'..."

run_command az containerapp update \
  --name "$FULL_NAME" \
  --resource-group "$AZURE_RESOURCE_GROUP_NAME" \
  --yaml "$YAML_CONFIG_PATH"
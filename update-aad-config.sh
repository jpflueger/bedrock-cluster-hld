#!/bin/bash

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")"; pwd -P)
TF_DIR=""
CONFIG_FILE="$ROOT_DIR/config/centralus.yaml"

function usage {
  echo "Usage: $(basename $0) [-c CONFIG_FILE] -t TERRAFORM_DIRECTORY" 2>&1
  echo "Update fabrikate definition with Azure Managed Identities from Terraform output"
  echo "    -c CONFIG_FILE            Path to yaml configuration file used by Fabrikate. Defaults to '$ROOT_DIR/config/centralus.yaml'"
  echo "    -t TERRAFORM_DIRECTORY    Directory containing Terraform module scaffolded by Bedrock"
  exit 1
}

# if no input argument found, exit the script with usage
if [[ ${#} -eq 0 ]]; then
   usage
fi

# Parse options
while getopts ":ht:" opt; do
  case ${opt} in
    t )
      TF_DIR=$OPTARG
      ;;
    c )
      CONFIG_FILE=$OPTARG
      ;;
    h )
      usage
      ;;
    ?)
      echo "Invalid option: -${OPTARG}."
      echo
      usage
      exit 2
      ;;
  esac
done

# ensure the terraform directory exists
if [[ ! -d "$TF_DIR/.terraform/" ]]; then
  echo "Invalid usage: $TF_DIR must exist and contain '.terraform' directory"
  echo
  usage
fi

# ensure the config file exists
if [[ ! -f "$CONFIG_FILE" ]]; then
  touch $CONFIG_FILE
fi

# try to load a dotenv file if it exists above the generated project directory
if [[ -f "$TF_DIR/../../.env" ]]; then
  source "$TF_DIR/../../.env"
fi

IDENTITIES=$(cd "$TF_DIR" && terraform output -json application_identities)
for row in $(echo "${IDENTITIES}" | jq -r '.[] | @base64'); do
  ID_CLIENT_ID=$(echo ${row} | base64 --decode | jq -r '.client_id')
  ID_RESRCE_ID=$(echo ${row} | base64 --decode | jq -r '.id')
  ID_NAME=$(echo ${row} | base64 --decode | jq -r '.name')

  TMP_FILE=$(mktemp)

  yq write ${TMP_FILE} 'name' "${ID_NAME}" -i --style double
  yq write ${TMP_FILE} 'namespace' 'default' -i --style double
  yq write ${TMP_FILE} 'type' '0' -i
  yq write ${TMP_FILE} 'resourceID' "${ID_RESRCE_ID}" -i --style double
  yq write ${TMP_FILE} 'clientID' "${ID_CLIENT_ID}" -i --style double
  yq write ${TMP_FILE} 'binding.name' "${ID_NAME}-binding" -i --style double
  yq write ${TMP_FILE} 'binding.selector' "${ID_NAME}" -i --style double

  yq prefix ${TMP_FILE} 'subcomponents.pod-identity.subcomponents.aad-pod-identity.config.azureIdentities[+]' -i

  yq merge ${CONFIG_FILE} ${TMP_FILE} -i
done

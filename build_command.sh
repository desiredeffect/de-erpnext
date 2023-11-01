# Command to build containers. This is how additional apps and modules are incorporated into the images.

# Load in the .env file to grab our token
. ./.env

# Run a replacement on the token title with SED & export as a base64 var
json_contents=$(cat ./apps.json)
json_contents=$(echo "$json_contents" | sed "s/\${DE_MACRS_PAT}/$DE_MACRS_PAT/g")
export APPS_JSON_BASE64=$(echo $json_contents | base64 -w 0)

docker build \
  --build-arg=FRAPPE_PATH=https://github.com/frappe/frappe \
  --build-arg=FRAPPE_BRANCH=version-15 \
  --build-arg=PYTHON_VERSION=3.11.6 \
  --build-arg=NODE_VERSION=18.18.2 \
  --build-arg=APPS_JSON_BASE64=$APPS_JSON_BASE64 \
  --tag=desiredeffect/erpnext-de:$ERPNEXT_VERSION \
  --file=images/custom/Containerfile .

  #--no-cache \
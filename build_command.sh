# Command to build containers. This is how additional apps and modules are incorporated into the images.

export APPS_JSON_BASE64=$(base64 -w 0 ./apps.json)
. ./.env

docker build \
  --build-arg=FRAPPE_PATH=https://github.com/frappe/frappe \
  --build-arg=FRAPPE_BRANCH=version-14 \
  --build-arg=PYTHON_VERSION=3.11.5 \
  --build-arg=NODE_VERSION=18.17.1 \
  --build-arg=APPS_JSON_BASE64=$APPS_JSON_BASE64 \
  --tag=desiredeffect/erpnext-hrms:$ERPNEXT_VERSION \
  --file=images/custom/Containerfile .
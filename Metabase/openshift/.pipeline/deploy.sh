#!/bin/sh
set +e -ux
# Login to OpenShift and select project
oc login --token="${OPENSHIFT_TOKEN}" --server="${OPENSHIFT_SERVER}"

BACKUP_CONF="postgres=metabase-postgres:5432/metabase-postgres

0 1 * * * default ./backup.sh -s
0 4 * * * default ./backup.sh -s -v all
"

oc create configmap backup-conf --from-literal=backup.conf="$BACKUP_CONF" | oc apply -f -
oc label configmap backup-conf app=backup-container
oc process -f https://raw.githubusercontent.com/bcgov/"${REPO_NAME}"/main/Metabase/openshift/postgres/backup/backup-deploy.yaml NAME=backup-postgres IMAGE_NAMESPACE="${OPENSHIFT_NAMESPACE_NO_ENV}"-"${TARGET_ENV}" SOURCE_IMAGE_NAME=backup-postgres TAG_NAME=v1 BACKUP_VOLUME_NAME=backup-postgres-pvc -p BACKUP_VOLUME_SIZE=200Mi -p VERIFICATION_VOLUME_SIZE=200Mi -p ENVIRONMENT_NAME="${TARGET_ENV}" -p ENVIRONMENT_FRIENDLY_NAME='Metabase postgres DB Backups' \
| oc apply -f -

# Process and Add network policy
oc process -f "https://raw.githubusercontent.com/bcgov/${REPO_NAME}/main/Metabase/openshift/metabase.np.yaml" \
| oc apply -f -

# Process and Add Postgresql for Metabase
oc process -f "https://raw.githubusercontent.com/bcgov/${REPO_NAME}/main/Metabase/openshift/postgres/postgres.yml"  -p NAMESPACE="${OPENSHIFT_NAMESPACE_NO_ENV}"-"${TARGET_ENV}" -p DB_PVC_SIZE=200Mi \
| oc apply -f -

# Process and create secret
oc process -f "https://raw.githubusercontent.com/bcgov/${REPO_NAME}/main/Metabase/openshift/metabase.secret.yaml" -p DB_HOST="${DB_HOST}" -p DB_PORT="${DB_PORT}" -p ADMIN_EMAIL="${MB_ADMIN_EMAIL}" \
| oc apply -f -

# Process and apply deployment template
oc process -f "https://raw.githubusercontent.com/bcgov/${REPO_NAME}/main/Metabase/openshift/metabase.dc.yaml" -p NAMESPACE="${OPENSHIFT_NAMESPACE_NO_ENV}"-"${TARGET_ENV}" -p PREFIX="${METABASE_APP_PREFIX}" \
| oc apply -f -

# Start rollout (if necessary) and follow it
oc rollout latest dc/"${APP_NAME}" 2> /dev/null \
|| true && echo "Rollout in progress"
oc logs -f dc/"${APP_NAME}"
# Get status, returns 0 if rollout is successful
oc rollout status dc/"${APP_NAME}"

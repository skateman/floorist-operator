#!/bin/bash

# New Floorist image used by the operator
NEW_FLOORIST_IMG="$(
    oc get deployment.apps -o jsonpath='{.items[?(.metadata.name=="floorist-operator-controller-manager")].spec.template.spec.containers[?(.name=="manager")].env[?(.name=="FLOORIST_IMAGE")].value}{"\n"}'
):$(
    oc get deployment.apps -o jsonpath='{.items[?(.metadata.name=="floorist-operator-controller-manager")].spec.template.spec.containers[?(.name=="manager")].env[?(.name=="FLOORIST_IMAGE_TAG")].value}{"\n"}'
)"

NAMESPACED_CRONJOBS=$(oc get cronjobs -l "service=floorist" \
                     -o jsonpath='{range .items[*]}{.metadata.namespace}:{.metadata.name}{"\n"}{end}' --all-namespaces)

if [[ -z "$NAMESPACED_CRONJOBS" ]]; then
    echo "ERROR: no cronjobs found"
    exit 1
fi

echo "----------------- Cronjobs found -----------------"
echo "$NAMESPACED_CRONJOBS"
echo "--------------------------------------------------"

# Setting IFS to newline to split multiline strings into arrays
IFS=$'\n'

NAMESPACED_CRONJOBS=($NAMESPACED_CRONJOBS)
for NAMESPACED_CRONJOB in "${NAMESPACED_CRONJOBS[@]}"; do
    NAMESPACE=$(echo "$NAMESPACED_CRONJOB" | awk -F ':' '{print $1}')
    CRONJOB=$(echo "$NAMESPACED_CRONJOB" | awk -F ':' '{print $2}')

    SUCCESS=$(oc get job -l "pod=$CRONJOB" -o jsonpath='{range .items[*]}{..succeeded}{"\n"}{end}' -n "$NAMESPACE")

    if [[ -z "$SUCCESS" ]]; then
        echo "ERROR: cronjob $CRONJOB has not created any jobs in namespace $NAMESPACE"
        exit 1
    fi

    SUCCESS=($SUCCESS)
    for SUCCESS_BOOLEAN in "${SUCCESS[@]}"; do
        if [[ "$SUCCESS_BOOLEAN" != "1" ]]; then
            echo "ERROR: cronjob $CRONJOB has a failed run in namespace $NAMESPACE"
            exit 1
        fi
    done

    # Comparing operator's image with the image used by the (cron)jobs
    JOB_IMAGES=$(oc get job -l "pod=${CRONJOB}" -o jsonpath='{range .items[*]}{..image}{"\n"}{end}' -n $NAMESPACE)
    JOB_IMAGES=($JOB_IMAGES)

    for JOB_IMAGE in "${JOB_IMAGES[@]}"; do
        if [[ "$NEW_FLOORIST_IMG" != "$JOB_IMAGE" ]]; then
            echo "ERROR: cronjob $CRONJOB in namespace $NAMESPACE is not configured with the newest Floorist image"
            echo "Operator's image: $NEW_FLOORIST_IMG"
            echo "Image used by the cronjob: $JOB_IMAGE"
            exit 1
        fi
    done
done

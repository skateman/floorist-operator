#!/bin/bash

NAMESPACED_CRONJOBS=$(oc get cronjobs -l "service=floorist" \
                     -o jsonpath='{range .items[*]}{.metadata.namespace}:{.metadata.name}{"\n"}{end}' --all-namespaces)

if [[ -z "$NAMESPACED_CRONJOBS" ]]; then
    echo "ERROR: no cronjobs found"
    exit 1
fi

echo "----------------- Cronjobs found -----------------"
echo "$NAMESPACED_CRONJOBS"
echo "--------------------------------------------------"

while IFS=$'\n' read -r NAMESPACED_CRONJOB; do
    NAMESPACE=$(echo "$NAMESPACED_CRONJOB" | awk -F ':' '{print $1}')
    CRONJOB=$(echo "$NAMESPACED_CRONJOB" | awk -F ':' '{print $2}')

    SUCCESS=$(oc get job -l "pod=$CRONJOB" -o jsonpath='{..succeeded}{"\n"}' -n "$NAMESPACE")

    if [[ -z "$SUCCESS" ]]; then
        echo "ERROR: cronjob $CRONJOB has not created any jobs in namespace $NAMESPACE"
        exit 1
    fi

    if [[ "$SUCCESS" != "1" ]]; then
        echo "ERROR: cronjob $CRONJOB has not created successful jobs in namespace $NAMESPACE"
        exit 1
    fi
done <<< "$NAMESPACED_CRONJOBS"

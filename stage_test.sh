#!/bin/bash

NEW_FLOORIST_IMG="$(
    oc get deployment.apps -l "control-plane=controller-manager" \
    -o jsonpath='{.items[].spec.template.spec.containers[?(.name=="manager")].env[?(.name=="FLOORIST_IMAGE")].value}{"\n"}'
):$(
    oc get deployment.apps -l "control-plane=controller-manager" \
    -o jsonpath='{.items[].spec.template.spec.containers[?(.name=="manager")].env[?(.name=="FLOORIST_IMAGE_TAG")].value}{"\n"}'
)"

MANAGER_TIMESTAMP=$(
    oc get deployment.apps -l "control-plane=controller-manager" \
    -o jsonpath='{.items[].metadata.managedFields[?(.manager=="kubectl-client-side-apply")].time}{"\n"}'
)

NAMESPACED_CRONJOBS=$(
    oc get cronjobs -l "service=floorist" -o \
    jsonpath='{range .items[*]}{.metadata.namespace};{.metadata.name};{.spec.suspend}{"\n"}{end}' --all-namespaces
)

if [[ -z "$NAMESPACED_CRONJOBS" ]]; then
    echo "ERROR: no cronjobs found"
    exit 1
fi

echo "----------------- Cronjobs found -----------------"
echo "$(echo "$NAMESPACED_CRONJOBS" | cut -d ';' -f 1,2)"
echo "--------------------------------------------------"

# Setting IFS to newline to split multiline strings into arrays
IFS=$'\n'

NAMESPACED_CRONJOBS=($NAMESPACED_CRONJOBS)
for NAMESPACED_CRONJOB in "${NAMESPACED_CRONJOBS[@]}"; do
    NAMESPACE=$(echo "$NAMESPACED_CRONJOB" | cut -d ";" -f 1)
    CRONJOB=$(echo "$NAMESPACED_CRONJOB" | cut -d ";" -f 2)

    # Skipping suspended cronjobs
    if [[ "$(echo "$NAMESPACED_CRONJOB" | cut -d ";" -f 3)" == "true" ]]; then
        echo "INFO: cronjob $CRONJOB is suspended in namespace $NAMESPACE"
        continue
    fi

    JOBS=$(oc get jobs -l "pod=$CRONJOB" -o jsonpath='{range .items[*]}{.status.succeeded};{.metadata.name}{"\n"}{end}' -n "$NAMESPACE")

    # Testing if any jobs that have failed were created after the operator's last deployment
    JOBS=($JOBS)
    for JOB_RESULT in "${JOBS[@]}"; do
        RESULT=$(echo "$JOB_RESULT" | cut -d ";" -f 1)

        if [[ "$RESULT" != "1" ]]; then
            JOB=$(echo "$JOB_RESULT" | cut -d ";" -f 2)
            JOB_FAILURE_TIME=$(oc get job "$JOB" -o jsonpath='{.status.startTime}{"\n"}' -n "$NAMESPACE")

            if [[ "$JOB_FAILURE_TIME" > "$MANAGER_TIMESTAMP" ]]; then
                echo "ERROR: cronjob $CRONJOB has a failed run in namespace $NAMESPACE"
                echo "Failed job: $JOB"
                exit 1
            fi
        fi
    done

    # Comparing operator's image with the image used by the newest job
    LATEST_JOB_IMAGE=$(
        oc get job -l "pod=${CRONJOB}" --sort-by=.metadata.creationTimestamp \
        -o jsonpath='{.items[-1].spec.template.spec.containers[].image}{"\n"}' -n $NAMESPACE
    )

    if [[ "$NEW_FLOORIST_IMG" != "$LATEST_JOB_IMAGE" ]]; then
        echo "ERROR: newest job of cronjob $CRONJOB in namespace $NAMESPACE is not configured with the newest Floorist image"
        echo "Operator's image: $NEW_FLOORIST_IMG"
        echo "Image used by the latest job: $LATEST_JOB_IMAGE"
        exit 1
    fi
done

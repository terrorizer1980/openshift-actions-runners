#!/bin/sh
# Based on https://github.com/bbrowning/github-runner/blob/master/entrypoint.sh

set -eE

if [ -z "${GITHUB_OWNER:-}" ]; then
    echo "Fatal: \$GITHUB_OWNER must be set in the environment"
    exit 1
fi

if [ -z "${GITHUB_DOMAIN:-}" ]; then
    echo "Connecting to public GitHub"
    GITHUB_DOMAIN="github.com"
    GITHUB_API_SERVER="api.github.com"
else
    echo "Connecting to GitHub server at '$GITHUB_DOMAIN'"
    GITHUB_API_SERVER="${GITHUB_DOMAIN}/api/v3"
fi

echo "GitHub API server is '$GITHUB_API_SERVER'"

if [ -z "${GITHUB_REPOSITORY:-}" ] && [ -n "${GITHUB_REPO:-}" ]; then
    GITHUB_REPOSITORY=$GITHUB_REPO
fi

# https://docs.github.com/en/free-pro-team@latest/rest/reference/actions#create-a-registration-token-for-an-organization

registration_url="https://${GITHUB_DOMAIN}/${GITHUB_OWNER}${GITHUB_REPOSITORY:+/$GITHUB_REPOSITORY}"

if [ -z "${GITHUB_PAT:-}" ]; then
    echo "GITHUB_PAT not set in the environment. Automatic runner removal will be disabled."
    echo "Visit ${registration_url}/settings/actions/runners to manually force removal of runner."
fi

if [ -z "${RUNNER_TOKEN:-}" ]; then
    if [ -z "${GITHUB_REPOSITORY:-}" ]; then
        echo "Runner is scoped to organization '${GITHUB_OWNER}'"
        echo "View runner status at https://${GITHUB_DOMAIN}/organizations/${GITHUB_OWNER}/settings/actions"

        token_url="https://${GITHUB_API_SERVER}/orgs/${GITHUB_OWNER}/actions/runners/registration-token"
    else
        echo "Runner is scoped to repository '${GITHUB_OWNER}/${GITHUB_REPOSITORY}'"
        echo "View runner status at https://${GITHUB_DOMAIN}/${GITHUB_OWNER}/${GITHUB_REPOSITORY}/settings/actions"

        token_url="https://${GITHUB_API_SERVER}/repos/${GITHUB_OWNER}/${GITHUB_REPOSITORY}/actions/runners/registration-token"
    fi
    echo "Obtaining runner token from ${token_url}"

    payload=$(curl -sSfLX POST -H "Authorization: token ${GITHUB_PAT}" ${token_url})
    export RUNNER_TOKEN=$(echo $payload | jq .token --raw-output)
    echo "Obtained registration token"
else
    echo "Using RUNNER_TOKEN from environment"
fi

labels_arg=""
if [ -n "${RUNNER_LABELS:-}" ]; then
    labels_arg="--labels $RUNNER_LABELS"
else
    echo "No labels provided"
fi

if [ -n "${RUNNER_TOKEN:-}" ]; then
    set -x
    ./config.sh \
        --name $(hostname) \
        --token ${RUNNER_TOKEN} \
        --url ${registration_url} \
        --work ${RUNNER_WORKDIR} \
        ${labels_arg} \
        --unattended \
        --replace
    set +x
fi

remove() {
    payload=$(curl -sSfLX POST -H "Authorization: token ${GITHUB_PAT}" ${token_url%/registration-token}/remove-token)
    export REMOVE_TOKEN=$(echo $payload | jq .token --raw-output)

    ./config.sh remove --unattended --token "${REMOVE_TOKEN}"
}

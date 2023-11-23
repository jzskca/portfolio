#!/bin/bash
set -eu

function abort {
    echo "$@" >&2
    exit 1
}

for app in aws git kubectl yq; do
    which $app >/dev/null 2>&1 || abort Missing app: $app
done

args="$(
    getopt \
        -o 'a:,c:,f:,n:,p,s:' \
        -l 'aws-profile:,context:,frontend:,namespace:,production,sentry-auth-token:' \
        -n "$0" \
        -- "$@"
)"
eval set -- "$args"

aws_profile=${AWS_PROFILE:-default}
frontend_dir=
k8s_context=$(kubectl config current-context)
k8s_namespace=
production=
sentry_auth_token=

while true; do
    case "$1" in
        '-a' | '--aws-profile')
            aws_profile="$2"
            shift 2
            continue
            ;;
        '-c' | '--context')
            k8s_context="$2"
            shift 2
            continue
            ;;
        '-f' | '--frontend-dir')
            frontend_dir="$2"
            shift 2
            continue
            ;;
        '-n' | '--namespace')
            k8s_namespace="$2"
            shift 2
            continue
            ;;
        '-p' | '--production')
            production=1
            shift
            continue
            ;;
        '-s' | '--sentry-auth-token')
            sentry_auth_token="$2"
            shift 2
            continue
            ;;
        '--')
            shift
            break
            ;;
        *)
            abort Unknown argument \""$1"\"
            ;;
    esac
done

if [ $# -gt 0 ]; then
    abort Trailing arguments: "$@"
fi

function require_arg() {
    if [ -z "$1" ]; then
        abort "$2" is required.
    fi
}

require_arg "$frontend_dir" --frontend/-f
require_arg "$k8s_namespace" --namespace/-n
require_arg "$sentry_auth_token" --sentry-auth-token/-s

revision=$(git log --format=%h --abbrev=8 HEAD^\!)

git_status_file=$(mktemp)
git status --porcelain >"$git_status_file"
dirty=$({ grep -qv '^??' "$git_status_file" && echo 1; } || true)
untracked=$({ grep -q '^??' "$git_status_file" && echo 1; } || true)
rm "$git_status_file"

echo "AWS profile (-a): $aws_profile"
echo "Frontend directory (-f): $frontend_dir"
echo "Kubernetes context (-c): $k8s_context"
echo "Kubernetes namespace (-n): $k8s_namespace"
echo "Sentry authentication token (-s): ${sentry_auth_token:0:12}…"
echo
echo "Branch: $(git branch --show-current)"
echo "Revision: $revision"
echo
[[ -n $untracked ]] && echo There are UNTRACKED FILES in the working tree.
[[ -n $dirty ]] && echo The working tree is DIRTY.
[[ -z $untracked && -z $dirty ]] && echo The working tree is clean ✨
echo
echo This is a "$(test "$production" && echo PRODUCTION || echo STAGING)" build.
echo

read -rp "Enter PROCEED to proceed: " proceed
if [ "$proceed" != PROCEED ]; then
    echo Aborting.
    exit 2
fi
echo

function aws {
    command aws --profile "$aws_profile" "$@"
}
function kubectl {
    command kubectl --context "$k8s_context" --namespace "$k8s_namespace" "$@"
}

build_selector=:$(test "$production" && echo prod || echo staging)
docker_repo="$(
    aws ecr describe-repositories --output text |
        grep ^REPOSITORIES |
        head -1 |
        cut -f7 |
        cut -d/ -f1
)"
image_prefix=$(test "$production" || echo demo)

aws ecr get-login-password | docker login --username AWS --password-stdin "$docker_repo"

function build_push {
    path="$1"
    prefix="$2"
    shift 2
    tag="$docker_repo/$frontend_dir/$path:${prefix:+$prefix-}$revision"
    docker build -t "$tag" "$@"
    docker push "$tag"
}

build_push backend "" --target backend backend

for target in celery-beat celery-worker static; do
    build_push backend $target --target $target backend
done

build_push frontend "$image_prefix" \
    --build-arg BUILD_SELECTOR="$build_selector" \
    --build-arg SENTRY_AUTH_TOKEN="$sentry_auth_token" \
    --build-arg SENTRY_RELEASE="$revision" \
    "$frontend_dir"

build_push meeting "$image_prefix" \
    --build-arg BUILD_SELECTOR="$build_selector" \
    --build-arg SENTRY_AUTH_TOKEN="$sentry_auth_token" \
    --build-arg SENTRY_RELEASE="$revision" \
    meeting

yq -i '.images[].newTag |= sub("[a-f0-9]{8}$", "'"$revision"'")' kustomize/kustomization.yaml

kubectl apply -k kustomize

git add kustomize/kustomization.yaml
git commit -m "Release $(date +%Y-%m-%d)"

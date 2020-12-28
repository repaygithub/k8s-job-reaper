#!/bin/bash -e

export REGION=us-west-2
export REALM=org
export AWS_PROFILE=${REALM}_shared_services_admin
export SHARED_SERVICES_ACCOUNT_NUM=232624534379

rootdir=$(pwd)

tag=$(git rev-parse HEAD)
current_branch=$(git branch | grep \* | cut -d ' ' -f2)
dry_run=true

declare -a images_to_build
if [ "${IMAGE}" != "" ]; then
  images_to_build+=(${IMAGE})
fi

if [ ${#images_to_build[@]} -eq 0 ]; then
  images_to_build=("k8reaper")
fi

if [ "${current_branch}" == "master" ]; then
  dry_run=false
fi

function run_test() {
  name=$1
  echo "******"
  echo "Running functional test for ${name} image. Note that you need to be on the vpn for some of the tests to be successful".
  echo "******"
  ./tests/${name}_test.sh
}
# set dry_run var based on branch name -
# please do not push a new image unless you're doing it from branch master
function build_and_push() {
  name=$1
  echo "*****"
  echo "Building ${name}"
  echo "*****"
  docker build . --target=${name} -t ${name}:${tag} -t ${name}:latest
  run_test ${name}

  set -x
  if [ "${dry_run}" == false ]; then
    echo "pushing ${name} to ecr"
    ./push_to_docker_registry.sh \
      --image-name ${name} \
      --tag-value ${tag} \
      --build-number $(whoami) \
      --branch-name ${current_branch} \
      --repo-type ecr \
      --aws-account-num ${SHARED_SERVICES_ACCOUNT_NUM} \
      --aws-region ${REGION} \
      --aws-profile ${AWS_PROFILE}
    echo "${name} successfully pushed to ecr"

  else
    echo "*****"
    echo "script is running in dry run mode"
    echo "Done building ${name}"
    echo "*****"
  fi
  set +x
}

for image in "${images_to_build[@]}"; do
  build_and_push ${image}
done

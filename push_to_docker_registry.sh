#! /bin/bash -e

scriptName="push_to_docker_registry.sh"
version="2.0.0"
maintainer="Antonio Tamer, Slack alias @at"
# Set Flags
# -----------------------------------
# Flags which can be overridden by user input.
# Default values are below
# -----------------------------------
#args=() #TODO
image_name=""
tag_value=""
build_number=""
branch_name=""
repo_type=""
aws_account_num=""
aws_region=""
aws_profile=""

function die() {
  die() { echo "$*" 1>&2 ; exit 1; }
}

function errorIfEmpty() {
  name=$1
  value=$2
  if [[ ${value} == "" ]]; then
    die "${name}" is required
  fi
}

function mainScript() {
  errorIfEmpty "image_name" ${image_name}
  errorIfEmpty "tag_value" ${tag_value}
  errorIfEmpty "build_number" ${build_number}
  errorIfEmpty "branch_name" ${branch_name}
  errorIfEmpty "repo_type" ${repo_type}

  docker_target_image_name=""

  if [[ ${repo_type} == "ecr" ]]; then
    errorIfEmpty "aws_account_num" $aws_account_num
    errorIfEmpty "aws_region" ${aws_region}
    errorIfEmpty "aws_profile" ${aws_profile}

    $(aws ecr --profile ${aws_profile} get-login --no-include-email --region ${aws_region})
    docker_target_image_name="${aws_account_num}.dkr.ecr.${aws_region}.amazonaws.com/${image_name}"
  fi

  docker tag ${image_name}:${tag_value} ${docker_target_image_name}:latest
  docker tag ${image_name}:${tag_value} ${docker_target_image_name}:${tag_value}
  docker tag ${image_name}:${tag_value} ${docker_target_image_name}:local_build_${build_number}
  docker tag ${image_name}:${tag_value} ${docker_target_image_name}:${branch_name}
  docker tag ${image_name}:${tag_value} ${docker_target_image_name}:latest
  docker push ${docker_target_image_name}:${tag_value}
  docker push ${docker_target_image_name}:local_build_${build_number}
  docker push ${docker_target_image_name}:${branch_name}
  docker push ${docker_target_image_name}:latest
}

############## Begin Options and Usage ###################
# Print usage
usage() {
  echo -n "${scriptName} [OPTION]... [FILE]...

This pushes a build docker image to a docker registry. It also tags
the image before push.

Supported registries are:
  - ecr

 Options:
  --image-name      Name of Docker image *required *required
  --build-number    The jenkins build number for this job *required
  --branch-name     The branch in git *required
  --tag-value       Git commit hash *required
  --version         Output version information and exit
  -h, --help        Display this help and exit
"
}

# Iterate over options breaking -ab into -a -b when needed and --foo=bar into
# --foo bar
optstring=h
unset options
while (($#)); do
  case $1 in
    # If option is of type -ab
    -[!-]?*)
      # Loop over each character starting with the second
      for ((i=1; i < ${#1}; i++)); do
        c=${1:i:1}

        # Add current char to options
        options+=("-$c")

        # If option takes a required argument, and it's not the last char make
        # the rest of the string its argument
        if [[ $optstring = *"$c:"* && ${1:i+1} ]]; then
          options+=("${1:i+1}")
          break
        fi
      done
      ;;

    # If option is of type --foo=bar
    --?*=*) options+=("${1%%=*}" "${1#*=}") ;;
    # add --endopts for --
    --) options+=(--endopts) ;;
    # Otherwise, nothing special
    *) options+=("$1") ;;
  esac
  shift
done
set -- "${options[@]}"
unset options

# Print help if no arguments were passed.
# Uncomment to force arguments when invoking the script
# [[ $# -eq 0 ]] && set -- "--help"

# Read the options and set stuff
while [[ $1 = -?* ]]; do
  case $1 in
    -h|--help) usage >&2;;
    --version) echo "$(basename $0) ${version} ${maintainer}";;
    --image-name) image_name=$2; shift;;
    --build-number) build_number=$2; shift;;
    --branch-name) branch_name=$2; shift;;
    --tag-value) tag_value=$2; shift;;
    --repo-type) repo_type=$2; shift;;
    --aws-account-num) aws_account_num=$2; shift;;
    --aws-region) aws_region=$2; shift;;
    --aws-profile) aws_profile=$2; shift;;
    --endopts) shift; break ;;
    *) die "invalid option: '$1'." ;;
  esac
  shift
done

# Store the remaining part as arguments. #TODO
#args+=("$@")

############## End Options and Usage ###################

# Run your script
mainScript
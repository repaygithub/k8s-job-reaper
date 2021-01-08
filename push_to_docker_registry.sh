def statusCode = 0
def dry_run = true

def orgSharedServicesAccountNumber = '232624534379'
def orgSharedServicesProfile = 'org_shared_services_terraform'
def region = 'us-west-2'
def imagesToBuild = ["k8sops", "tfops", "tfops12", "tfops13", "packerops", "blackduckops", "blastdns", "yamale"]

def is_pr() {
  env.CHANGE_BRANCH && env.CHANGE_TARGET
}

if (is_pr() && env.CHANGE_TARGET == 'master') {
  dry_run = true
} else if (env.BRANCH_NAME == 'master') {
  dry_run = false
} else {
  echo 'failing as this job only supports master'
  currentBuild.result = 'FAILURE'
  return
}

podTemplate(
  containers: [
    containerTemplate(
      name: 'jnlp',
      image: 'jenkins/jnlp-slave:3.10-1-alpine',
      args: '${computer.jnlpmac} ${computer.name}',
      envVars: [
        envVar(key: 'JENKINS_TUNNEL', value: 'jenkins-agent:50000'         ),
        envVar(key: 'JENKINS_URL'   , value: 'http://jenkins-internal:8080'),
      ]
    ),
    containerTemplate(
      name: 'docker',
      image: "docker",
      ttyEnabled: true,
      command: 'cat',
      alwaysPullImage: true
    ),
    containerTemplate(
      name: 'k8sops',
      image: "232624534379.dkr.ecr.us-west-2.amazonaws.com/k8sops:latest",
      ttyEnabled: true,
      command: 'cat',
      alwaysPullImage: true
    )
  ],
  imagePullSecrets: ["quay.io"],
  envVars: [
    envVar(key: 'BUILD_NUMBER', value: "${env.BUILD_NUMBER}"),
    secretEnvVar(key: 'AWS_ACCESS_KEY_ID'    , secretName: 'aws-iam', secretKey: 'AWS_ACCESS_KEY_ID'),
    secretEnvVar(key: 'AWS_SECRET_ACCESS_KEY', secretName: 'aws-iam', secretKey: 'AWS_SECRET_ACCESS_KEY'),
  ],
  volumes: [
    hostPathVolume(mountPath: '/var/run/docker.sock', hostPath: '/var/run/docker.sock'),
  ]
){
  node(POD_LABEL) {
    try {
      notifySlack()
      def myRepo = checkout scm
      def gitCommit = myRepo.GIT_COMMIT
      def gitBranch = myRepo.GIT_BRANCH
      def images = imagesToBuild.join(" ")

      stage("prep build") {
          container('k8sops') {
            sh "mkdir -p ~/.docker"
            config_aws(region)
          }
      }
      stage("build images") {
        parallel createImages(imagesToBuild, gitCommit)
      }
      stage("push images") {
        parallel pushImages(imagesToBuild, gitCommit, gitBranch, region,
                            orgSharedServicesAccountNumber, orgSharedServicesProfile, dry_run)
      }

    } catch (e) {
      currentBuild.result = 'FAILURE'
      throw e
    }
    finally {
      notifySlack(currentBuild.result)
      stage("cleanup") {
        container('docker') {
            sh "echo all done"
        }
      }
    }
  }
}

def config_aws(region) {
  // Note: we use the config_aws.sh from the repo here because it doesn't exist
  // in a container for us at genesis.
  sh (
    label: "Create AWS config profiles for ${region}",
    script: """
        $WORKSPACE/scripts/config_aws.sh --region ${region}
    """
  )
}

def notifySlack(String buildStatus = 'STARTED') {
  buildStatus = buildStatus ?: 'SUCCESS'

  def color
  def emoji

  if (buildStatus == 'STARTED') {
    color = '#D4DADF'
    emoji = ':shaler-hair:'
  } else if (buildStatus == 'SUCCESS') {
    color = '#BDFFC3'
    emoji = ':shaler_happy_face:'
  } else if (buildStatus == 'UNSTABLE') {
    color = '#FFFE89'
    emoji = ':shaler_neutral-annoyed:'
  } else {
    color = '#FF9FA1'
    emoji = ':shaler_frown:'
  }

  def msg = "${buildStatus}: `${env.JOB_NAME}` #${env.BUILD_NUMBER}: ${emoji}\n${env.RUN_DISPLAY_URL}"

  slackSend(color: color, message: msg)
}

def createImages(images, tag) {
  def opMap = [:]
  images.each { image ->
    opMap[image] = {
        stage ("build ${image}") {
            container('docker') {
                sh """
                docker build --network=host . --target=${image} -t ${image}:${tag} -t ${image}:latest
                """
            }
        }
        stage ("test ${image}") {
            container('k8sops') {
                sh """
                ${WORKSPACE}/tests/${image}_test.sh
                """
            }
        }
    }
  }
  return opMap
}

def pushImages(images, tag, branch, region, orgSharedServicesAccountNumber, orgSharedServicesProfile, dry_run) {
  def opMap = [:]
  images.each { image ->
    opMap[image] = {
        stage ("push ${image}") {
            container('k8sops') {
                if (dry_run) {
                    sh "echo dry run: skipping push to ecr"
                } else {
                    // sh "apk add docker"
                    sh "echo pushing ${image} to ecr"
                    sh """
                       ${WORKSPACE}/push_to_docker_registry.sh \
                         --image-name ${image} \
                         --tag-value ${tag} \
                         --build-number ${env.BUILD_NUMBER} \
                         --branch-name ${branch} \
                         --repo-type ecr \
                         --aws-account-num ${orgSharedServicesAccountNumber} \
                         --aws-region ${region} \
                         --aws-profile ${orgSharedServicesProfile}
                       """
                }
            }
        }
    }
  }
  return opMap
}
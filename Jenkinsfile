def is_prod() {
  env.TAG_NAME && env.TAG_NAME ==~ /v\d*\.\d*\.\d*/
}

def is_uat() {
  env.BRANCH_NAME == 'master'
}

// TODO remove when complete
def is_dev() {
  env.BRANCH_NAME == 'develop'
}

def is_pr() {
  if (env.CHANGE_ID) {
    return true
  }
  return false
}

def label = "worker-${UUID.randomUUID().toString()}"
def statusCode = 0
def region           = "us-west-2"
def region_id        = "usw2"
def dry_run          = is_pr()
def cluster_color    = "black"
def k8s_envs         = [""]
def orgSharedServicesAccountNumber = '232624534379'
def orgSharedServicesProfile = 'org_shared_services_admin'
def githubRepo = "git@github.com:repaygithub/gloo.git"
def imagesToBuild = ["k8reaper"]
def repayDevopsBaseImageTag        = "7496bd229ec97d516762fb0d13a095ae7e963aa4"
def repo_name            = "k8s-job-reaper"

def k8sAccounts = [
    'uat': '713631314575',
    'org': '460458929819',
    'dev': '564327313136',
    'sandbox': '063619347804',
    'prod': '374263412026',
]

def envRealms = [
     'dev':     'corp',
     'uat':     'corp',
     'org':     'org',
     'sandbox': 'cde',
     'prod':    'cde',
]
def envApplyOrder = [
  "0_${cluster_color}_${region_id}",
]

if (is_dev() || (is_pr() && env.CHANGE_TARGET == 'develop')) {
  k8s_envs      = ['dev']
} else if (is_uat() || (is_pr() && env.CHANGE_TARGET == 'master')) {
  k8s_envs      = ['uat', 'org']
} else if (is_prod()) {
  k8s_envs      = ['sandbox', 'prod']
} else {
  echo 'failing as this job only supports master, develop pushes and semantic versioned tags'
  currentBuild.result = 'FAILURE'
  return
}

podTemplate(
  label: label,
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
      name: 'repay-devops',	
      image: "232624534379.dkr.ecr.us-west-2.amazonaws.com/tfops:${repayDevopsBaseImageTag}",	
      ttyEnabled: true,	
      command: 'cat',	
      alwaysPullImage: true,	
    ),
    containerTemplate(
      name: 'k8sops',
      image: "232624534379.dkr.ecr.us-west-2.amazonaws.com/k8sops:${repayDevopsBaseImageTag}",
      ttyEnabled: true,
      command: 'cat',
      alwaysPullImage: true
    )
  ],
  envVars: [
    envVar(key: 'BUILD_NUMBER', value: "${env.BUILD_NUMBER}"),
    envVar(key: 'REALM'                , value: "${envRealms}"                ),
    envVar(key: 'COLOR'                , value: "${cluster_color}"        ),
    envVar(key: 'REGION'               , value: "${region}"               ),
    envVar(key: 'REGION_ID'            , value: "${region_id}"            ),
    envVar(key: 'KUBE_ENV'             , value: "${k8s_envs}"            ),
    envVar(key: 'DRY_RUN'              , value: "${dry_run}"              ),
    envVar(key: 'ORIGIN_REPO_NAME'     , value: "${repo_name}"            ),
    envVar(key: 'K8S_ACTIVE_COLOR'     , value: "${cluster_color}"        ),
    secretEnvVar(key: 'AWS_ACCESS_KEY_ID'    , secretName: 'aws-iam', secretKey: 'AWS_ACCESS_KEY_ID'),
    secretEnvVar(key: 'AWS_SECRET_ACCESS_KEY', secretName: 'aws-iam', secretKey: 'AWS_SECRET_ACCESS_KEY')
  ],
  volumes: [
    hostPathVolume(mountPath: '/var/run/docker.sock', hostPath: '/var/run/docker.sock'),
  ]
){
  node(label) {
    try {
      def myRepo = checkout scm
      def gitCommit = myRepo.GIT_COMMIT
      def gitBranch = myRepo.GIT_BRANCH
      def images = imagesToBuild.join(" ")
      k8s_envs.each { k8s_env ->
        def realm = envRealms[k8s_env]
        def k8sAccount = k8sAccounts[k8s_env]
        environment {
            REALM = realm
            KUBE_ENV = k8s_env
        }
        if(realm == null || realm.isEmpty()) {
          echo "Will not complete run for ${k8s_env} due to no realm configuration found for it."
          return
        }
        if(dry_run) {
          echo "Pipeline running with dry run turned on"
        }     
        stage("prep build-${k8s_env}") {
            container('k8sops') {
              sh "mkdir -p ~/.docker"
              sh """
              /scripts/config_aws.sh --k8s-env ${k8s_env} --region ${region}
              """
            }
        }
        stage("build images") {
          parallel createImages(imagesToBuild, gitCommit)
        }
        stage("push images") {
          parallel pushImages(imagesToBuild, gitCommit, gitBranch, region,
                              orgSharedServicesAccountNumber, orgSharedServicesProfile, dry_run)
        }
        stage("gomplate and kustomize ${k8s_env}") {
          container('k8sops') {
            sh """
            /scripts/config_aws.sh --k8s-env ${realm}_${k8s_env} --region ${region}
            export REALM=${realm}
            export KUBE_ENV=${k8s_env}
            /gitops/gomplates.sh
            DRY_RUN=true /gitops/kustomize.sh
            """

            if(!is_pr()) {
              input(message: "Apply K8s changes?")

              sh """
              export REALM=${realm}
              export KUBE_ENV=${k8s_env}
              /gitops/kustomize.sh
              """
            }
          }
        }
      }
    } catch (e) {
      currentBuild.result = 'FAILURE'
      throw e
    }
    finally {
      stage("cleanup") {
        container('docker') {
            sh "echo all done"
        }
      }
    }
  }
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
                // set up credentials for org ss
                sh "/scripts/config_aws.sh --region ${region}"
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
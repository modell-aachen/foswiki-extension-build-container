node {
  currentBuild.displayName = "#${BUILD_NUMBER} | ${RELEASE_STRING} | ${GITHUB_REPOSITORY}"
}

pipeline {
    agent {
      label "master"
    }
    environment {
        BUILD_DIR = "/var/lib/jenkins/workspace/qwiki-build-extension"
        JOB_BUILD_DIR = "/var/lib/jenkins/workspace/qwiki-build-extension/$BUILD_NUMBER"
        RMS_AUTH_TOKEN = credentials('6a6cdfed-3d05-4bc2-a45e-36190c5769cc')
    }
    stages {
        stage('Prepare Workspace') {
            steps {
              sh '''
                if [ ! -d "${BUILD_DIR}" ]; then
                  mkdir ${BUILD_DIR};
                fi
                if [ ! -d "${JOB_BUILD_DIR}" ]; then
                  mkdir ${JOB_BUILD_DIR};
                fi
              '''
            }
        }
        stage('Run foswiki extension build container') {
            agent {
                docker {
                    image 'quay.io/modac/foswiki-extension-build-container'
                    args '-e DEPLOY_PATH=$JOB_BUILD_DIR -v $BUILD_DIR:$BUILD_DIR:rw,z --entrypoint=""'
                    reuseNode true
                    alwaysPull true
                }
            }
            environment {
                GITHUB_AUTH_TOKEN = credentials('87e330a0-ce35-4301-a524-40d6141f355b')
            }
            steps {
                dir(JOB_BUILD_DIR) {
                    sh "node /src/dist/main.js"
                }
            }
        }
        stage('Upload to gcloud') {
            agent {
                docker {
                    image 'google/cloud-sdk:alpine'
                    label 'docker'
                    args '-u root:root'
                    alwaysPull true
                }
            }
            steps {
                //staging: 87bc00fa-3063-4693-851c-63e86800eee7   prod: c949741f-f995-4faf-8f04-e1995eee99db
                withCredentials([file(credentialsId: '87bc00fa-3063-4693-851c-63e86800eee7', variable: 'SERVICE_ACCOUNT_FILE')]) {
                    sh "gcloud auth activate-service-account --key-file=$SERVICE_ACCOUNT_FILE"
                }
                sh "gsutil -m cp -r . \"gs://${GCLOUD_BUCKET}/${GITHUB_REF}/${GITHUB_REPOSITORY}\""
            }
        }
        stage('Notify RMS') {
            steps {
                dir(JOB_BUILD_DIR) {
                  sh '''
                    curl --fail -X POST -i -H \"rms-auth-token: ${RMS_AUTH_TOKEN}\" \"${UPLOAD_DESTINATION}?checkoutTarget=${GITHUB_REF}&component=${COMPONENT_ID}\";
                  '''
                }
            }
        }
    }
    post {
      always {
          sh "rm -r ${JOB_BUILD_DIR}"
          sh "rm -r ${JOB_BUILD_DIR}@tmp"
      }
      failure {
          sh '''
            curl --fail -X POST -i -H \"rms-auth-token: ${RMS_AUTH_TOKEN}\" \"${FAILURE_DESTINATION}?checkoutTarget=${GITHUB_REF}&component=${COMPONENT_ID}\";
          '''
      }
    }
}

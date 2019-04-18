pipeline {
    agent {
      label "master"
    }
    environment {
        JOB_BUILD_DIR = "/var/lib/jenkins/workspace/qwiki-build-extension/$BUILD_NUMBER"
    }
    stages {
        stage('Prepare Workspace') {
            steps {
              sh '''
                if [ ! -d "${JOB_BUILD_DIR}" ]; then
                  mkdir ${JOB_BUILD_DIR};
                  mkdir ${JOB_BUILD_DIR}/deploy;
                fi
              '''
            }
        }
        stage('Run foswiki extension build container') {
            agent {
                docker {
                    image 'quay.io/modac/foswiki-extension-build-container'
                    args '-e DEPLOY_PATH=$JOB_BUILD_DIR/deploy --entrypoint=""'
                    alwaysPull true
                    reuseNode true
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
        stage('Upload to RMS') {
            environment {
                RMS_AUTH_TOKEN = credentials('6a6cdfed-3d05-4bc2-a45e-36190c5769cc')
            }
            steps {
                dir(JOB_BUILD_DIR) {
                  sh '''
                    cd deploy;
                    tar zcf ../build.tar.gz *.tgz *_installer metadata.json;
                    cd ..;
                    curl -i -H \"rms-auth-token: ${RMS_AUTH_TOKEN}\" -F \"build=@build.tar.gz\" \"${UPLOAD_DESTINATION}?buildId=${BUILD_ID}\";
                  '''
                }
            }
        }
        stage('Cleanup Workspace') {
            steps {
                sh "echo rm -r ./${JOB_BUILD_DIR}"
            }
        }
    }
}

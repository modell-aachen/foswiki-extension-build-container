pipeline {
    agent none
    stages {
        stage('Run foswiki extension build container') {
            agent {
                docker {
                    image 'quay.io/modac/foswiki-extension-build-container'
                    reuseNode true
                    args '-u root:root -v $WORKSPACE/deploy:/deploy --entrypoint=""'
                    customWorkspace "/var/lib/jenkins/workspace/qwiki-build-extension/$BUILD_NUMBER"
                    alwaysPull true
                }
            }
            environment {
                GITHUB_AUTH_TOKEN = credentials('87e330a0-ce35-4301-a524-40d6141f355b')
            }
            steps {
                sh "node /src/dist/main.js"
            }
        }
        stage('Upload to RMS') {
            agent any
            environment {
                RMS_AUTH_TOKEN = credentials('6a6cdfed-3d05-4bc2-a45e-36190c5769cc')
            }
            steps {
                sh "cd ${BUILD_NUMBER}/deploy && tar zcf ../build.tar.gz *"
                sh "curl -i -H \"rms-auth-token: ${RMS_AUTH_TOKEN}\" -F \"build=@${BUILD_NUMBER}/build.tar.gz\" \"${UPLOAD_DESTINATION}?buildId=${BUILD_ID}\""
            }
        }
        stage('Cleanup Workspace') {
            agent any
            steps {
                sh "rm -r ./${BUILD_NUMBER}"
            }
        }
    }
}

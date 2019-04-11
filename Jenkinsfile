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
    }
}

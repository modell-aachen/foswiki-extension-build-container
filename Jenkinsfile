pipeline {
    agent none
    stages {
        stage('Run foswiki extension build container') {
            agent {
                docker {
                    image 'quay.io/modac/foswiki-extension-build-container'
                    args '-v $WORKSPACE/deploy:/deploy --env GITHUB_ORGANIZATION --env GITHUB_REPOSITORY --env GITHUB_AUTH_TOKEN --env GITHUB_REF'
                }
            }
            environment {
                GITHUB_AUTH_TOKEN = credentials('87e330a0-ce35-4301-a524-40d6141f355b')
            }
        }
    }
}

node {
    def workspace = pwd()
    def BUILD_DIR = "${workspace}/qwiki-build-extension"
    def JOB_BUILD_DIR = "${workspace}/qwiki-build-extension/$BUILD_NUMBER"

    stage('Prepare Workspace') {
        sh """
            if [ ! -d \"${BUILD_DIR}\" ]; then
                mkdir ${BUILD_DIR};
            fi
            if [ ! -d \"${JOB_BUILD_DIR}\" ]; then
                mkdir ${JOB_BUILD_DIR};
            fi
        """
    }

    stage('Run foswiki extension build container') {
        docker.image('quay.io/modac/foswiki-extension-build-container').inside("-e DEPLOY_PATH=${JOB_BUILD_DIR} -v ${BUILD_DIR}:${BUILD_DIR}:rw,z --entrypoint=\"\"") { c ->
            dir(JOB_BUILD_DIR) {
                withCredentials([string(credentialsId: '87e330a0-ce35-4301-a524-40d6141f355b', variable: 'GITHUB_AUTH_TOKEN')]) {
                    sh "node /src/dist/main.js"
                }
            }
        }
    }

    stage('Upload to gcloud') {
        docker.image('google/cloud-sdk:alpine').inside('-u root:root') { c ->
            //staging: 87bc00fa-3063-4693-851c-63e86800eee7   prod: c949741f-f995-4faf-8f04-e1995eee99db
            withCredentials([file(credentialsId: 'c949741f-f995-4faf-8f04-e1995eee99db', variable: 'SERVICE_ACCOUNT_FILE')]) {
                sh "gcloud auth activate-service-account --key-file=$SERVICE_ACCOUNT_FILE"
            }
            sh "gsutil -m cp -r . \"gs://${GCLOUD_BUCKET}/${GITHUB_REF}/${GITHUB_REPOSITORY}\""
        }
    }

    stage('Notify RMS') {
        dir(JOB_BUILD_DIR) {
            withCredentials([string(credentialsId: '6a6cdfed-3d05-4bc2-a45e-36190c5769cc', variable: 'RMS_TOKEN')]) {
                sh """
                    curl --fail -X POST -i -H \"rms-auth-token: $RMS_AUTH_TOKEN\" \"${UPLOAD_DESTINATION}?checkoutTarget=${GITHUB_REF}&component=${COMPONENT_ID}\";
                """
            }
        }
    }
}

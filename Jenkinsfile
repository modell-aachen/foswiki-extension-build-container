#!groovy

node ("docker") {
    def workspace = pwd()
    def BUILD_DIR = "${workspace}/qwiki-build-extension"
    def JOB_BUILD_DIR = "${workspace}/qwiki-build-extension/$BUILD_NUMBER"

    try {

      stage('Prepare Workspace') {
          def buildDir = new File(BUILD_DIR)
          def jobBuildDir = new File(JOB_BUILD_DIR)

          if( !buildDir.exists() ) {
              buildDir.mkdirs()
          }

          if( !jobBuildDir.exists() ) {
              jobBuildDir.mkdirs()
          }
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
          docker.image('google/cloud-sdk:alpine').inside("-e CLOUDSDK_CONFIG=/tmp/config -u root:root -v ${JOB_BUILD_DIR}:${JOB_BUILD_DIR}:rw,z") { c ->
              dir(JOB_BUILD_DIR) {
                //staging: 87bc00fa-3063-4693-851c-63e86800eee7   prod: c949741f-f995-4faf-8f04-e1995eee99db
                withCredentials([file(credentialsId: 'c949741f-f995-4faf-8f04-e1995eee99db', variable: 'SERVICE_ACCOUNT_FILE')]) {
                    sh "gcloud auth activate-service-account --key-file=$SERVICE_ACCOUNT_FILE"
                }
                sh "gsutil -m cp -r . \"gs://${GCLOUD_BUCKET}/${GITHUB_REF}/${GITHUB_REPOSITORY}\""
              }
          }
      }

      stage('Notify RMS') {
          dir(JOB_BUILD_DIR) {
              withCredentials([string(credentialsId: '6a6cdfed-3d05-4bc2-a45e-36190c5769cc', variable: 'RMS_TOKEN')]) {
                  sh """
                      curl --fail -X POST -i -H \"rms-auth-token: $RMS_TOKEN\" \"${UPLOAD_DESTINATION}?checkoutTarget=${GITHUB_REF}&component=${COMPONENT_ID}\";
                  """
              }
          }
      }

    }catch(err) {
      echo "Pipeline failed. Caught error: "
      echo err.getMessage()
      echo "Going to notify RMS about failure..."

      withCredentials([string(credentialsId: '6a6cdfed-3d05-4bc2-a45e-36190c5769cc', variable: 'RMS_TOKEN')]) {
          sh """
            curl --fail -X POST -i -H \"rms-auth-token: $RMS_TOKEN\" \"${FAILURE_DESTINATION}?checkoutTarget=${GITHUB_REF}&component=${COMPONENT_ID}\";
          """
      }

      error("Failed")

    }finally{
      // allways cleanup
      sh "rm -r ${JOB_BUILD_DIR}"
      sh "rm -r ${JOB_BUILD_DIR}@tmp"
    }
}

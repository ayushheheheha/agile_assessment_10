
pipeline {
    agent any


    parameters {
        booleanParam(name: 'PUSH_IMAGE', defaultValue: true, description: 'Push the image to Docker Hub')
        booleanParam(name: 'DEPLOY',     defaultValue: true, description: 'Deploy to Kubernetes (needs PUSH_IMAGE)')
    }

    environment {
        DOCKERHUB_USER  = 'YOUR_DOCKERHUB_USERNAME'
        DOCKERHUB_CREDS = 'dockerhub-creds'
        KUBE_CREDS      = 'kubeconfig'
        IMAGE_NAME      = 'pm-dashboard'
        IMAGE           = "${DOCKERHUB_USER}/${IMAGE_NAME}:v${BUILD_NUMBER}"
        IMAGE_LATEST    = "${DOCKERHUB_USER}/${IMAGE_NAME}:latest"
    }

    options {
        disableConcurrentBuilds()
        buildDiscarder(logRotator(numToKeepStr: '10'))
    }

    stages {

        stage('Checkout') {
            steps {
                checkout scm      
                script {
                    writeFile file: 'build-info.txt',
                              text: "build=${BUILD_NUMBER}\nimage=${IMAGE}\ncommit=${env.GIT_COMMIT}\n"
                }
            }
        }

       
        stage('Build & Test') {
            parallel {
                stage('Validate Dashboard') {
                    steps {
                        script {
                            def html = readFile('index.html')
                            for (key in ['Equipment Monitoring', 'TEMP_LIMIT', 'VIB_LIMIT']) {
                                if (!html.contains(key)) { error("index.html is missing: ${key}") }
                            }
                            echo 'Dashboard checks passed'
                        }
                    }
                }
                stage('Validate Deployment Files') {
                    steps {
                        script {
                            def yaml = readFile('deployment.yaml')
                            for (key in ['IMAGE_PLACEHOLDER', 'readinessProbe', 'kind: Service']) {
                                if (!yaml.contains(key)) { error("deployment.yaml is missing: ${key}") }
                            }
                            if (!fileExists('Dockerfile')) { error('Dockerfile not found') }
                            echo 'Deployment file checks passed'
                        }
                    }
                }
                stage('Docker Build') {
                    steps {
                        script { run("docker build -t ${IMAGE} -t ${IMAGE_LATEST} .") }
                    }
                }
            }
        }

        stage('Smoke Test Container') {
            steps {
                script {
                    def name = "pm-smoke-${BUILD_NUMBER}"
                    run("docker run -d --name ${name} ${IMAGE}")
                    sleep 3
                    def rc = runRC("docker exec ${name} wget -qO- http://127.0.0.1/")
                    run("docker rm -f ${name}")
                    if (rc != 0) { error('Smoke test failed: dashboard is not served by the container') }
                    echo 'Smoke test passed'
                }
            }
        }

        // Pipeline type 3: CONDITIONAL STAGE EXECUTION
        stage('Push to Docker Hub') {
            when { expression { params.PUSH_IMAGE } }
            steps {
                script {
                    withCredentials([usernamePassword(credentialsId: env.DOCKERHUB_CREDS,
                                                      usernameVariable: 'DH_USER',
                                                      passwordVariable: 'DH_PASS')]) {
                        if (isUnix()) {
                            sh 'echo "$DH_PASS" | docker login -u "$DH_USER" --password-stdin'
                        } else {
                            bat 'echo %DH_PASS%| docker login -u %DH_USER% --password-stdin'
                        }
                        run("docker push ${IMAGE}")
                        run("docker push ${IMAGE_LATEST}")
                    }
                }
            }
        }

        stage('Deploy to Kubernetes') {
            when { expression { params.DEPLOY && params.PUSH_IMAGE } }
            steps {
                script {
                    // Insert the freshly built image tag into the manifest
                    def manifest = readFile('deployment.yaml').replace('IMAGE_PLACEHOLDER', env.IMAGE)
                    writeFile file: 'deploy-rendered.yaml', text: manifest

                    withCredentials([file(credentialsId: env.KUBE_CREDS, variable: 'KUBECONFIG')]) {
                        run('kubectl apply -f deploy-rendered.yaml')

                        // Wait for the rollout; non-zero exit = rollout failed / timed out
                        def rc = runRC('kubectl rollout status deployment/pm-dashboard --timeout=90s')

                        if (rc != 0) {
                            echo "ROLLOUT FAILED for ${env.IMAGE} - rolling back to the previous stable release"
                            run('kubectl rollout undo deployment/pm-dashboard')
                            run('kubectl rollout status deployment/pm-dashboard --timeout=90s')
                            showClusterState()
                            error("Release ${env.IMAGE} failed its rollout. Automatically rolled back to the previous stable release.")
                        }
                    }
                }
            }
        }

        stage('Verify Deployment') {
            when { expression { params.DEPLOY && params.PUSH_IMAGE } }
            steps {
                script {
                    withCredentials([file(credentialsId: env.KUBE_CREDS, variable: 'KUBECONFIG')]) {
                        showClusterState()
                    }
                    echo 'Deployment healthy. Open http://localhost:30080'
                }
            }
        }
    }

    post {
        always {
            // Pipeline type 4: ARCHIVE BUILD ARTIFACTS
            archiveArtifacts artifacts: 'index.html, Dockerfile, deployment.yaml, deploy-rendered.yaml, build-info.txt',
                             allowEmptyArchive: true, fingerprint: true
        }
        success { echo "Build #${BUILD_NUMBER} succeeded: ${IMAGE}" }
        failure { echo "Build #${BUILD_NUMBER} failed - check the stage that is marked red" }
    }
}

// ---------- helpers (work on Linux and Windows agents) ----------
def run(String cmd)   { isUnix() ? sh(cmd) : bat(cmd) }
def runRC(String cmd) { return isUnix() ? sh(script: cmd, returnStatus: true) : bat(script: cmd, returnStatus: true) }

def showClusterState() {
    run('kubectl get deployment pm-dashboard -o wide')
    run('kubectl get pods -l app=pm-dashboard')
    run('kubectl rollout history deployment/pm-dashboard')
}
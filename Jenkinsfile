pipeline {
    agent any

    environment {
        GIT_REPO        = "https://github.com/himanshu085/employee_api_eks.git"
        GIT_CRED        = "git-credential"
        DOCKER_IMAGE    = "employee-api:latest"
        DOCKER_REGISTRY = "himanshu085/employee-api"
        DOCKER_CRED     = "docker-hub-credentials"
        TERRAFORM_DIR   = "terraform"
        K8S_DIR         = "k8s"
        CLUSTER_VERSION = "1.28"
        AWS_REGION      = "us-east-1"
        KUBECONFIG      = "/var/lib/jenkins/.kube/config"
    }

    stages {

        stage('Checkout Code') {
            steps {
                echo "📥 Cloning Employee API repository..."
                checkout([$class: 'GitSCM',
                    branches: [[name: '*/main']],
                    userRemoteConfigs: [[url: "${GIT_REPO}", credentialsId: "${GIT_CRED}"]]
                ])
            }
        }

        stage('Build & Unit Tests') {
            agent {
                docker {
                    image 'golang:1.22-alpine'
                    args '-u 0:0'
                }
            }
            steps {
                echo "🔨 Building & testing Employee API..."
                sh '''
                    go mod tidy
                    go test ./... -v
                    CGO_ENABLED=0 GOOS=linux go build -o employee-api .
                '''
            }
        }

        stage('Dockerize & Push') {
            steps {
                echo "🐳 Building & pushing Docker image..."
                withCredentials([usernamePassword(credentialsId: "${DOCKER_CRED}", usernameVariable: 'DOCKER_USER', passwordVariable: 'DOCKER_PASS')]) {
                    sh '''
                        echo "$DOCKER_PASS" | docker login -u "$DOCKER_USER" --password-stdin
                        docker build -t ${DOCKER_IMAGE} .
                        docker tag ${DOCKER_IMAGE} ${DOCKER_REGISTRY}:${BUILD_NUMBER}
                        docker tag ${DOCKER_IMAGE} ${DOCKER_REGISTRY}:latest
                        docker push ${DOCKER_REGISTRY}:${BUILD_NUMBER}
                        docker push ${DOCKER_REGISTRY}:latest
                    '''
                }
            }
        }

        stage('Terraform Init & Apply') {
            steps {
                withCredentials([
                    string(credentialsId: 'aws-access-key-id', variable: 'AWS_ACCESS_KEY_ID'),
                    string(credentialsId: 'aws_secret_access_key', variable: 'AWS_SECRET_ACCESS_KEY')
                ]) {
                    dir("${TERRAFORM_DIR}") {
                        writeFile file: 'terraform.tfvars', text: """
environment          = "dev"
vpc_cidr             = "10.0.0.0/16"
public_subnet_cidrs  = ["10.0.1.0/24", "10.0.2.0/24"]
private_subnet_cidrs = ["10.0.101.0/24", "10.0.102.0/24"]
cluster_name         = "employee-eks"
cluster_version      = "${CLUSTER_VERSION}"
app_image            = "${DOCKER_REGISTRY}:${BUILD_NUMBER}"
"""
                        sh """
                            export AWS_DEFAULT_REGION=${AWS_REGION}
                            terraform init
                            terraform apply -auto-approve -var-file=terraform.tfvars
                            terraform output -raw eks_cluster_name > ../cluster_name.txt
                        """
                    }
                }
            }
        }

        stage('Patch Deployment YAML') {
            steps {
                echo "✏️ Updating deployment.yaml with Docker build tag..."
                sh """
                    sed -i "s|image: himanshu085/employee-api:latest|image: ${DOCKER_REGISTRY}:${BUILD_NUMBER}|g" ${K8S_DIR}/deployment.yaml
                """
            }
        }

        stage('Deploy to Kubernetes') {
            steps {
                withCredentials([
                    string(credentialsId: 'aws-access-key-id', variable: 'AWS_ACCESS_KEY_ID'),
                    string(credentialsId: 'aws_secret_access_key', variable: 'AWS_SECRET_ACCESS_KEY')
                ]) {
                    script {
                        def clusterName = readFile('cluster_name.txt').trim()
                        sh """
                            export AWS_DEFAULT_REGION=${AWS_REGION}
                            echo "🔧 Configuring kubeconfig for cluster: ${clusterName}"
                            mkdir -p \$(dirname ${KUBECONFIG})
                            aws eks update-kubeconfig --name ${clusterName} --region ${AWS_REGION} --kubeconfig ${KUBECONFIG}

                            echo "🚀 Deploying manifests to Kubernetes..."
                            kubectl --kubeconfig=${KUBECONFIG} apply -f "${K8S_DIR}/deployment.yaml"
                            kubectl --kubeconfig=${KUBECONFIG} apply -f "${K8S_DIR}/service.yaml"
                            kubectl --kubeconfig=${KUBECONFIG} apply -f "${K8S_DIR}/ingress.yaml" || true

                            echo "⏳ Waiting for rollout..."
                            set +e
                            kubectl --kubeconfig=${KUBECONFIG} rollout status deployment/employee-api --timeout=300s
                            ROLL_OUT_STATUS=$?
                            set -e

                            if [ \$ROLL_OUT_STATUS -ne 0 ]; then
                                echo "❌ Rollout failed! Collecting debug info..."
                                kubectl --kubeconfig=${KUBECONFIG} get pods -l app=employee-api -o wide
                                kubectl --kubeconfig=${KUBECONFIG} describe pod -l app=employee-api || true
                                kubectl --kubeconfig=${KUBECONFIG} logs -l app=employee-api --tail=100 || true
                                exit 1
                            else
                                echo "✅ Rollout succeeded!"
                                kubectl --kubeconfig=${KUBECONFIG} wait --for=condition=ready pod -l app=employee-api --timeout=300s
                                echo "📜 Recent pod logs..."
                                kubectl --kubeconfig=${KUBECONFIG} logs -l app=employee-api --tail=50 || true
                            fi
                        """
                    }
                }
            }
        }

        stage('Post-Deployment Validation') {
            steps {
                withCredentials([
                    string(credentialsId: 'aws-access-key-id', variable: 'AWS_ACCESS_KEY_ID'),
                    string(credentialsId: 'aws_secret_access_key', variable: 'AWS_SECRET_ACCESS_KEY')
                ]) {
                    script {
                        def clusterName = readFile('cluster_name.txt').trim()
                        sh """
                            export AWS_DEFAULT_REGION=${AWS_REGION}
                            aws eks update-kubeconfig --name ${clusterName} --region ${AWS_REGION} --kubeconfig ${KUBECONFIG}
                        """

                        echo "🔎 Listing pods and services..."
                        sh "kubectl --kubeconfig=${KUBECONFIG} get pods -o wide"
                        sh "kubectl --kubeconfig=${KUBECONFIG} get svc"
                        sh "kubectl --kubeconfig=${KUBECONFIG} get ingress"

                        echo "🚀 Running internal smoke test..."
                        def podIP = sh(
                            script: "kubectl --kubeconfig=${KUBECONFIG} get pod -l app=employee-api -o jsonpath='{.items[0].status.podIP}'",
                            returnStdout: true
                        ).trim()

                        if (podIP) {
                            def url = "http://${podIP}:8080/api/v1/employee/health"
                            echo "💻 Health check URL: ${url}"
                            sh """
                                for i in {1..6}; do
                                    curl -sf ${url} && break || sleep 10
                                done
                            """
                        } else {
                            echo "⚠️ No pods found to test health endpoint."
                        }
                    }
                }
            }
        }
    }

    post {
        always {
            script {
                try {
                    def userChoice = input(
                        id: 'DestroyApproval',
                        message: "⚠️ Do you want to destroy all Terraform resources?",
                        parameters: [choice(name: 'ACTION', choices: ['Destroy', 'Keep Infra'], description: 'Select action')]
                    )
                    if (userChoice == 'Destroy') {
                        echo "⚡ Destroying Terraform-managed infrastructure..."
                        withCredentials([
                            string(credentialsId: 'aws-access-key-id', variable: 'AWS_ACCESS_KEY_ID'),
                            string(credentialsId: 'aws_secret_access_key', variable: 'AWS_SECRET_ACCESS_KEY')
                        ]) {
                            dir("${TERRAFORM_DIR}") {
                                sh """
                                    export AWS_DEFAULT_REGION=${AWS_REGION}
                                    terraform init
                                    terraform destroy -auto-approve -var-file=terraform.tfvars || true
                                """
                            }
                        }
                    } else {
                        echo "✅ Keeping infrastructure as is."
                    }
                } catch(err) {
                    echo "⏩ Skipping destroy prompt."
                }
            }
            echo "🧹 Cleaning workspace..."
            cleanWs()
        }
        success { echo "✅ Pipeline succeeded!" }
        failure { echo "❌ Pipeline failed!" }
    }
}

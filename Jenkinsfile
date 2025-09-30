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
                            aws eks update-kubeconfig --name ${clusterName} --region ${AWS_REGION}

                            echo "🚀 Deploying manifests to Kubernetes..."
                            kubectl apply -f "${K8S_DIR}/deployment.yaml"
                            kubectl apply -f "${K8S_DIR}/service.yaml"
                            kubectl apply -f "${K8S_DIR}/ingress.yaml" || true

                            echo "⏳ Waiting for rollout..."
                            kubectl rollout status deployment/employee-api --timeout=300s

                            echo "✅ Ensuring pods are ready..."
                            kubectl wait --for=condition=ready pod -l app=employee-api --timeout=300s
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
                            aws eks update-kubeconfig --name ${clusterName} --region ${AWS_REGION}
                        """

                        echo "🔎 Listing pods and services..."
                        sh "kubectl get pods -o wide"
                        sh "kubectl get svc"
                        sh "kubectl get ingress"

                        echo "🚀 Running internal smoke test..."
                        def podIP = sh(
                            script: "kubectl get pod -l app=employee-api -o jsonpath='{.items[0].status.podIP}'",
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
            echo "🧹 Cleaning workspace..."
            cleanWs()
        }
        success { echo "✅ Pipeline succeeded!" }
        failure { echo "❌ Pipeline failed!" }
    }
}

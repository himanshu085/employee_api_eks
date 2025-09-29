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

        stage('Pre-Check Existing Infra') {
            steps {
                script {
                    def infraExists = false
                    dir("${TERRAFORM_DIR}") {
                        if (fileExists('terraform.tfstate')) {
                            echo "⚠️ Existing Terraform state found!"
                            infraExists = true
                        }
                    }

                    if (infraExists) {
                        def userChoice = input(
                            id: 'InfraAction',
                            message: "Existing infrastructure detected. What do you want to do?",
                            parameters: [choice(name: 'ACTION', choices: ['Destroy & Fresh Deploy', 'Keep Existing Infra'], description: 'Select action')]
                        )

                        if (userChoice == 'Destroy & Fresh Deploy') {
                            echo "⚡ Destroying existing Terraform infrastructure..."
                            withCredentials([
                                string(credentialsId: 'aws-access-key-id', variable: 'AWS_ACCESS_KEY_ID'),
                                string(credentialsId: 'aws_secret_access_key', variable: 'AWS_SECRET_ACCESS_KEY')
                            ]) {
                                dir("${TERRAFORM_DIR}") {
                                    sh """
                                        export AWS_DEFAULT_REGION=${AWS_REGION}
                                        terraform init
                                        terraform destroy -auto-approve || true
                                    """
                                }
                            }
                        } else {
                            echo "✅ Keeping existing infrastructure."
                        }
                    } else {
                        echo "✅ No existing infrastructure detected, proceeding normally."
                    }
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
                            terraform output -raw employee_api_service_dns > ../employee_api_service_dns.txt || true
                        """
                    }
                }
            }
        }

        stage('Patch Deployment YAML') {
            steps {
                echo "✏️ Updating deployment.yaml with Docker build tag..."
                sh """
                    sed -i "s|image: himanshu085/employee_service:latest|image: ${DOCKER_REGISTRY}:${BUILD_NUMBER}|g" ${K8S_DIR}/deployment.yaml
                """
            }
        }

        stage('Deploy to Kubernetes') {
            steps {
                script {
                    docker.image('amazon/aws-cli:2.15.38').inside('-u 0:0') {
                        withCredentials([
                            string(credentialsId: 'aws-access-key-id', variable: 'AWS_ACCESS_KEY_ID'),
                            string(credentialsId: 'aws_secret_access_key', variable: 'AWS_SECRET_ACCESS_KEY')
                        ]) {
                            def clusterName = readFile('cluster_name.txt').trim()
                            sh """
                                aws eks --region ${AWS_REGION} update-kubeconfig --name ${clusterName}
                                kubectl apply -f "${K8S_DIR}/deployment.yaml"
                                kubectl apply -f "${K8S_DIR}/service.yaml"
                                kubectl apply -f "${K8S_DIR}/ingress.yaml" || true

                                echo "⏳ Waiting for deployment rollout..."
                                kubectl rollout status deployment/employee-api --timeout=180s
                            """
                        }
                    }
                }
            }
        }

        stage('Post-Deployment Validation') {
            steps {
                script {
                    def serviceDns = ""

                    // Try Terraform output first
                    if (fileExists('employee_api_service_dns.txt')) {
                        serviceDns = readFile('employee_api_service_dns.txt').trim()
                    }

                    // Fetch from Kubernetes if not found
                    if (!serviceDns) {
                        echo "⚠️ Terraform output not found, fetching service DNS from Kubernetes..."
                        docker.image('amazon/aws-cli:2.15.38').inside('-u 0:0') {
                            withCredentials([
                                string(credentialsId: 'aws-access-key-id', variable: 'AWS_ACCESS_KEY_ID'),
                                string(credentialsId: 'aws_secret_access_key', variable: 'AWS_SECRET_ACCESS_KEY')
                            ]) {
                                def clusterName = readFile('cluster_name.txt').trim()
                                sh "aws eks --region ${AWS_REGION} update-kubeconfig --name ${clusterName}"
                                serviceDns = sh(script: "kubectl get svc employee-api -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'", returnStdout: true).trim()
                            }
                        }
                    }

                    if (serviceDns) {
                        def url = "http://${serviceDns}/swagger/index.html"
                        echo "🚀 Running smoke test on ${url} ..."
                        sh """
                            for i in {1..6}; do
                                curl -sf ${url} && break || sleep 10
                            done
                        """
                    } else {
                        echo "⚠️ Employee API Service DNS not found, skipping smoke test."
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

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
                script {
                    echo "🐳 Building & pushing Docker image..."
                    withCredentials([usernamePassword(credentialsId: "${DOCKER_CRED}", usernameVariable: 'DOCKER_USER', passwordVariable: 'DOCKER_PASS')]) {
                        sh '''
                            echo "$DOCKER_PASS" | docker login -u "$DOCKER_USER" --password-stdin
                            docker build -t ${DOCKER_IMAGE} .
                            docker tag ${DOCKER_IMAGE} ${DOCKER_REGISTRY}:${BUILD_NUMBER}
                            docker push ${DOCKER_REGISTRY}:${BUILD_NUMBER}
                        '''
                    }
                }
            }
        }

        stage('Terraform Init') {
            steps {
                withCredentials([
                    string(credentialsId: 'aws-access-key-id', variable: 'AWS_ACCESS_KEY_ID'),
                    string(credentialsId: 'aws_secret_access_key', variable: 'AWS_SECRET_ACCESS_KEY')
                ]) {
                    dir("${TERRAFORM_DIR}") {
                        sh """
                            export AWS_DEFAULT_REGION=${AWS_REGION}
                            echo "🔍 Running Terraform init..."
                            terraform init -backend=false
                        """
                    }
                }
            }
        }

        stage('Apply Terraform Infra') {
            steps {
                script {
                    withCredentials([
                        string(credentialsId: 'aws-access-key-id', variable: 'AWS_ACCESS_KEY_ID'),
                        string(credentialsId: 'aws_secret_access_key', variable: 'AWS_SECRET_ACCESS_KEY')
                    ]) {
                        dir("${TERRAFORM_DIR}") {
                            // Generate terraform.tfvars dynamically
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
                                terraform plan -var-file=terraform.tfvars -out=tfplan
                                terraform apply -auto-approve tfplan
                                terraform output -raw eks_cluster_name > ../cluster_name.txt
                                terraform output -raw employee_api_service_dns > ../employee_api_service_dns.txt || true
                            """
                        }
                    }
                }
            }
        }

        stage('Patch Deployment YAML') {
            steps {
                script {
                    echo "✏️ Updating deployment.yaml with Docker build tag..."
                    sh """
                        sed -i "s|image: himanshu085/employee_service:latest|image: ${DOCKER_REGISTRY}:${BUILD_NUMBER}|g" ${K8S_DIR}/deployment.yaml
                    """
                }
            }
        }

        stage('Deploy to Kubernetes') {
            steps {
                script {
                    docker.image('bitnami/kubectl:latest').inside('-u 0:0') {
                        withCredentials([
                            string(credentialsId: 'aws-access-key-id', variable: 'AWS_ACCESS_KEY_ID'),
                            string(credentialsId: 'aws_secret_access_key', variable: 'AWS_SECRET_ACCESS_KEY')
                        ]) {
                            def clusterName = readFile('cluster_name.txt').trim()
                            sh """
                                aws eks --region ${AWS_REGION} update-kubeconfig --name ${clusterName}
                                kubectl apply -f ${K8S_DIR}/deployment.yaml
                                kubectl apply -f ${K8S_DIR}/service.yaml
                                kubectl apply -f ${K8S_DIR}/ingress.yaml || true

                                echo "⏳ Waiting for pods to be ready..."
                                kubectl wait --for=condition=ready pod -l app=employee-api --timeout=180s
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
                    if (fileExists('employee_api_service_dns.txt')) {
                        serviceDns = readFile('employee_api_service_dns.txt').trim()
                    }
                    if (serviceDns) {
                        def url = "http://${serviceDns}/swagger/index.html"
                        echo "🚀 Running smoke test on ${url} ..."
                        sh """
                            for i in {1..6}; do
                                curl -f ${url} && break || sleep 10
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

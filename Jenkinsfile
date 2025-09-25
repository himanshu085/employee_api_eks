pipeline {
    agent any
    environment {
        GIT_REPO        = "https://github.com/himanshu085/employee_api.git"
        GIT_CRED        = "git-credential"
        DOCKER_IMAGE    = "employee_api:latest"
        DOCKER_REGISTRY = "himanshu085/employee_service"
        DOCKER_CRED     = "docker-hub-credentials"
        TERRAFORM_DIR   = "terraform"
    }
    stages {
        stage('Checkout Code') {
            steps {
                echo "Cloning Employee API repository..."
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
                echo "Building & testing Employee API..."
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
                    echo "Building & pushing Docker image..."
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
        stage('Infra Provisioning with deployment via remote execution') {
            steps {
                withCredentials([
                    string(credentialsId: 'aws-access-key-id', variable: 'AWS_ACCESS_KEY_ID'),
                    string(credentialsId: 'aws_secret_access_key', variable: 'AWS_SECRET_ACCESS_KEY'),
                    file(credentialsId: 'PRIVATE_KEY', variable: 'SSH_KEY')
                ]) {
                    dir("${TERRAFORM_DIR}") {
                        echo "Running Terraform..."
                        sh """
                            export AWS_DEFAULT_REGION=us-east-1
                            terraform init
                            terraform plan -out=tfplan \
                              -var "app_image=${DOCKER_REGISTRY}:${BUILD_NUMBER}" \
                              -var "private_key_path=${SSH_KEY}"
                            terraform apply -auto-approve tfplan
                            terraform output -raw alb_dns > ../alb_dns.txt
                        """
                    }
                }
            }
        }
        
        stage('Post-Deployment Validation') {
            steps {
                script {
                    def albDns = readFile('alb_dns.txt').trim()
                    def healthUrl = "http://${albDns}/swagger/index.html"
                    echo "Running smoke test on ${healthUrl} ..."
                    sh "curl -f ${healthUrl} || exit 1"
                }
            }
        }
    }
    post {
        always {
            echo "🧹 Cleaning workspace..."
            script {
                def userChoice = input(
                    id: 'DestroyApproval',
                    message: 'Do you want to destroy the infrastructure?',
                    parameters: [choice(name: 'ACTION', choices: ['Destroy', 'Keep Infra'], description: 'Select action')]
                )
                if (userChoice == 'Destroy') {
                    echo "⚡ Destroying Terraform-managed infrastructure..."
                    withCredentials([
                        string(credentialsId: 'aws-access-key-id', variable: 'AWS_ACCESS_KEY_ID'),
                        string(credentialsId: 'aws_secret_access_key', variable: 'AWS_SECRET_ACCESS_KEY'),
                        file(credentialsId: 'PRIVATE_KEY', variable: 'SSH_KEY')
                    ]) {
                        dir("${TERRAFORM_DIR}") {
                            sh """
                                export AWS_DEFAULT_REGION=us-east-1
                                terraform destroy -auto-approve \
                                  -var "app_image=${DOCKER_REGISTRY}:${BUILD_NUMBER}" \
                                  -var "private_key_path=${SSH_KEY}"
                            """
                        }
                    }
                } else {
                    echo "✅ Skipping destroy, infrastructure is preserved."
                }
            }
            cleanWs()
        }
        success {
            echo "✅ Pipeline succeeded!"
        }
        failure {
            echo "❌ Pipeline failed!"
        }
    }
}

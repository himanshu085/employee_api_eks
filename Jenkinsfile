pipeline {
    agent any
    environment {
        GIT_REPO        = "https://github.com/himanshu085/employee_api_eks.git"
        GIT_CRED        = "git-credential"
        DOCKER_IMAGE    = "employee-api:latest"
        DOCKER_REGISTRY = "himanshu085/employee-api"
        DOCKER_CRED     = "docker-hub-credentials"
        TERRAFORM_DIR   = "terraform/eks"
        NETWORK_DIR     = "terraform/network"
        K8S_DIR         = "k8s"
        CLUSTER_VERSION = "1.27"
        AWS_REGION      = "us-east-1"
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

        stage('Get Network Outputs') {
            steps {
                withCredentials([
                    string(credentialsId: 'aws-access-key-id', variable: 'AWS_ACCESS_KEY_ID'),
                    string(credentialsId: 'aws_secret_access_key', variable: 'AWS_SECRET_ACCESS_KEY')
                ]) {
                    dir("${NETWORK_DIR}") {
                        sh """
                            export AWS_DEFAULT_REGION=${AWS_REGION}
                            terraform output -raw vpc_id > ../vpc_id.txt
                            terraform output -json private_subnets > ../private_subnets.json
                            terraform output -json public_subnets > ../public_subnets.json
                        """
                    }
                }
            }
        }

        stage('Provision EKS with Terraform') {
            steps {
                withCredentials([
                    string(credentialsId: 'aws-access-key-id', variable: 'AWS_ACCESS_KEY_ID'),
                    string(credentialsId: 'aws_secret_access_key', variable: 'AWS_SECRET_ACCESS_KEY')
                ]) {
                    script {
                        def vpcId = readFile('../vpc_id.txt').trim()
                        def privateSubs = readFile('../private_subnets.json').trim()
                        def publicSubs  = readFile('../public_subnets.json').trim()

                        dir("${TERRAFORM_DIR}") {
                            writeFile file: 'terraform.tfvars', text: """
cluster_name = "employee-eks"
cluster_version = "${CLUSTER_VERSION}"
vpc_id = "${vpcId}"
private_subnets = ${privateSubs}
public_subnets = ${publicSubs}
app_image = "${DOCKER_REGISTRY}:${BUILD_NUMBER}"
"""
                            sh """
                                export AWS_DEFAULT_REGION=${AWS_REGION}
                                terraform init
                                terraform plan -out=tfplan
                                terraform apply -auto-approve tfplan
                                terraform output -raw cluster_name > ../cluster_name.txt
                                terraform output -raw cluster_endpoint > ../cluster_endpoint.txt
                            """
                        }
                    }
                }
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
                            aws eks --region ${AWS_REGION} update-kubeconfig --name ${clusterName}
                            kubectl apply -f ${K8S_DIR}/deployment.yaml
                            kubectl apply -f ${K8S_DIR}/service.yaml
                            kubectl apply -f ${K8S_DIR}/ingress.yaml || true
                        """
                    }
                }
            }
        }

        stage('Post-Deployment Validation') {
            steps {
                script {
                    echo "Waiting for LoadBalancer to come up..."
                    sh "sleep 60"
                    def svc = sh(script: "kubectl get svc employee-service -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'", returnStdout: true).trim()
                    def url = "http://${svc}/swagger/index.html"
                    echo "Running smoke test on ${url} ..."
                    sh "curl -f ${url} || exit 1"
                }
            }
        }
    }

    post {
        always {
            echo "🧹 Cleaning workspace..."
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

pipeline {
    agent any

    environment {
        GIT_REPO        = 'https://github.com/himanshu085/employee-api.git'
        GIT_CRED        = 'github-credentials'
        AWS_REGION      = 'us-east-1'
        NETWORK_DIR     = 'terraform/network'
        EKS_DIR         = 'terraform/eks'
        K8S_DIR         = 'k8s'
    }

    stages {
        stage('Checkout Code') {
            steps {
                checkout([$class: 'GitSCM',
                    branches: [[name: '*/main']],
                    userRemoteConfigs: [[url: "${GIT_REPO}", credentialsId: "${GIT_CRED}"]]
                ])
                stash includes: '**/*', name: 'source'
            }
        }

        stage('Apply Network Module') {
            steps {
                unstash 'source'
                withCredentials([
                    string(credentialsId: 'aws-access-key-id', variable: 'AWS_ACCESS_KEY_ID'),
                    string(credentialsId: 'aws_secret_access_key', variable: 'AWS_SECRET_ACCESS_KEY')
                ]) {
                    dir("${NETWORK_DIR}") {
                        sh '''
                            echo "Current dir: $(pwd)"
                            ls -la
                            export AWS_DEFAULT_REGION=${AWS_REGION}
                            terraform init -input=false
                            terraform apply -auto-approve -input=false
                            terraform output -raw vpc_id > ${WORKSPACE}/vpc_id.txt
                            terraform output -json private_subnets > ${WORKSPACE}/private_subnets.json
                            terraform output -json public_subnets > ${WORKSPACE}/public_subnets.json
                        '''
                    }
                }
            }
        }

        stage('Apply EKS Module') {
            steps {
                unstash 'source'
                withCredentials([
                    string(credentialsId: 'aws-access-key-id', variable: 'AWS_ACCESS_KEY_ID'),
                    string(credentialsId: 'aws_secret_access_key', variable: 'AWS_SECRET_ACCESS_KEY')
                ]) {
                    dir("${EKS_DIR}") {
                        sh '''
                            echo "Current dir: $(pwd)"
                            ls -la
                            export AWS_DEFAULT_REGION=${AWS_REGION}
                            terraform init -input=false
                            terraform apply -auto-approve -input=false
                        '''
                    }
                }
            }
        }

        stage('Deploy to Kubernetes') {
            steps {
                unstash 'source'
                withKubeConfig([credentialsId: 'eks-kubeconfig', contextName: '', serverUrl: '']) {
                    dir("${K8S_DIR}") {
                        sh '''
                            echo "Deploying K8s resources..."
                            kubectl apply -f deployment.yaml
                            kubectl apply -f service.yaml
                        '''
                    }
                }
            }
        }

        stage('Post-Deployment Validation') {
            steps {
                unstash 'source'
                sh '''
                    echo "Validating K8s service..."
                    kubectl get pods
                    kubectl get svc
                '''
            }
        }
    }

    post {
        always {
            script {
                try {
                    timeout(time: 5, unit: 'MINUTES') {
                        input message: "⚠️ Do you want to destroy all Terraform resources?", ok: "Destroy"
                        unstash 'source'

                        withCredentials([
                            string(credentialsId: 'aws-access-key-id', variable: 'AWS_ACCESS_KEY_ID'),
                            string(credentialsId: 'aws_secret_access_key', variable: 'AWS_SECRET_ACCESS_KEY')
                        ]) {
                            dir("${EKS_DIR}") {
                                sh '''
                                    export AWS_DEFAULT_REGION=${AWS_REGION}
                                    terraform destroy -auto-approve
                                '''
                            }
                            dir("${NETWORK_DIR}") {
                                sh '''
                                    export AWS_DEFAULT_REGION=${AWS_REGION}
                                    terraform destroy -auto-approve
                                '''
                            }
                        }
                    }
                } catch (err) {
                    echo "⏩ Destroy skipped by user or timeout."
                }
            }
            echo "🧹 Cleaning workspace..."
            cleanWs()
        }
        success {
            echo "✅ Pipeline completed successfully!"
        }
        failure {
            echo "❌ Pipeline failed!"
        }
    }
}

pipeline {
}


stage('Terraform Plan & Apply (EKS)') {
agent { docker { image 'hashicorp/terraform:1.5.7' } }
steps {
withCredentials([string(credentialsId: env.AWS_ACCESS_KEY, variable: 'AWS_ACCESS_KEY_ID'), string(credentialsId: env.AWS_SECRET_KEY, variable: 'AWS_SECRET_ACCESS_KEY')]) {
dir(env.TERRAFORM_DIR) {
sh '''
export AWS_DEFAULT_REGION=${AWS_REGION}
terraform init -input=false
terraform plan -out=tfplan -input=false -var "cluster_name=${CLUSTER_NAME}"
terraform apply -auto-approve tfplan
'''
}
}
}
}


stage('Deploy to EKS') {
agent { docker { image 'bitnami/kubectl:1.28' } }
steps {
withCredentials([string(credentialsId: env.AWS_ACCESS_KEY, variable: 'AWS_ACCESS_KEY_ID'), string(credentialsId: env.AWS_SECRET_KEY, variable: 'AWS_SECRET_ACCESS_KEY')]) {
sh '''
aws eks update-kubeconfig --name ${CLUSTER_NAME} --region ${AWS_REGION}
# apply manifests (deployment uses placeholder image)
kubectl apply -f k8s/
# update deployment image to the newly pushed tag
kubectl set image deployment/employee-api employee-api=${DOCKER_REGISTRY}:${BUILD_NUMBER} --record
kubectl rollout status deployment/employee-api --watch
'''
}
}
}


stage('Post-Deployment Validation') {
agent { docker { image 'curlimages/curl:7.88.1' } }
steps {
script {
// If ingress/ALB created by TF outputs, read it; here we try simple cluster access
sh '''
# try internal service first
kubectl get svc employee-api-svc || true
# if you have ALB hostname in terraform output, replace <ALB_HOST> and use curl
# curl -f http://<ALB_HOST>/api/v1/employee/health
'''
}
}
}
}


post {
success { echo "✅ Pipeline successful" }
failure { echo "❌ Pipeline failed" }
always {
echo 'Cleaning workspace...'
cleanWs()
}
}
}

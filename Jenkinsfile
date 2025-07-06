pipeline{
    agent any
    stages {
        stage('clean WorkSpace'){
            steps{
                cleanWs()
            }
        }
        stage('Clone Repository'){
            steps{
                git credentialsId: 'my_secret_token', branch: 'main', url: 'https://github.com/WalaaHijazi1/Deploy-Django-On-AWS.git'
            }
        }
        stage('access AWS'){
            steps{
                withCredentials([aws(credentialsId: 'aws_credentials')]){
                    sh 'aws --version'
                    sh 'aws ec2 describe-instances'
                }
            }
        }
        stage('Create ECR repository in AWS - First Step'){
            steps {
                dir('ecr_repository'){
                    sh 'terraform init'
                    sh 'terraform plan'
                }
            }
        }
        stage('Create ECR repository in AWS - Second Step'){
            steps {
                withCredentials([aws(credentialsId: 'aws_credentials')]){
                    dir('ecr_repository'){
                        sh 'terraform apply -auto-approve'
                        echo 'an ECR repo is just createed in your aws account.'
                    }
                }
            }
        }
        stage('Get Terraform Outputs'){
            steps{
                script{
                    def outputJson=sh(script= 'terraform output -json', returnStdout: true).trim()
                    def outputs = readJSON text: outputJson

                    # ECR output:
                    env.ECR_REPO = outputs["django_ecr_repo_url"]["value"]
                    echo "ECR amazon repo: ${env.ECR_REPO}"
                }
            }
        }
        stage('Create A Django Docker Image'){
            steps{
                dir('Django'){
                    withCredentials([aws(credentialsId: 'aws_credentials')]){
                        sh '''

                        # Login to ECR
                        aws ecr get-login-password --region ap-south-1 | docker login --username AWS --password-stdin ${env.ECR_REPO}

                        docker build -t django-service:latest .

                        # Tag it with ECR Repo
                        # docker tag django-service:latest 253490776843.dkr.ecr.ap-south-1.amazonaws.com/django-service:latest
                        docker tag django-service:latest ${env.ECR_REPO}/django-service:latest

                        # Push img into ECR Hub:
                        docker push ${env.ECR_REPO}/django-service:latest
                        '''
                    }
                }
            }
        }
        stage('Build The Main Infrastructure In AWS'){
            steps {
                dir('infrastructure'){
                    withCredentials([aws(credentialsId: 'aws_credentials')]){
                        sh 'terraform init'
                        sh 'terraform apply -auto-approve'
                    }
                }
            }
        }
        stage('Terraform Apply ECS') {
            steps {
                dir('terraform/ecs_cluster') {
                    withCredentials([aws(credentialsId: 'aws_credentials')]){
                        sh 'terraform init'
                        sh 'terraform apply -auto-approve'
                    }
                }
            }
        }
    }
    post {
    always {
        script {
            def attachments = []

            // Add state files from each folder
            def folders = ['infrastructure', 'ecs_cluster', 'ecr_repository']
            folders.each { folder ->
                def tfstatePath = "${folder}/terraform.tfstate"
                if (fileExists(tfstatePath)) {
                    attachments << tfstatePath
                }
            }

            emailext(
                to: 'hijaziwalaa69@gmail.com',
                subject: "Jenkins Pipeline Finished - ${currentBuild.result}",
                body: """Hello Walaa,

    Your Jenkins pipeline for deploying the Django app to AWS has finished with result: ${currentBuild.result}.

    Attached are the Terraform state/biuld.log files for your reference.

    Regards,
    Jenkins
    """,
                    attachLog: true,
                    attachmentsPattern: attachments.join(',')
                )
            }
        }
    }
}
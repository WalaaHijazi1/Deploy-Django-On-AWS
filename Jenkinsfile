pipeline {
    agent any
    stages {
        stage('Clean Workspace') {
            steps {
                cleanWs()
            }
        }
        stage('Clone Repository') {
            steps {
                git credentialsId: 'my_secret_token', branch: 'main', url: 'https://github.com/WalaaHijazi1/Deploy-Django-On-AWS.git'
            }
        }
        stage('Access AWS') {
            steps {
                withCredentials([aws(credentialsId: 'aws_credentials')]) {
                    sh 'aws --version'
                    sh 'aws ec2 describe-instances'
                }
            }
        }
        stage('Destroy All Terraform Modules') {
            steps {
                withCredentials([aws(credentialsId: 'aws_credentials')]) {
                    script {
                        def modules = ['ecs_cluster', 'infrastructure', 'ecr_repository']
                        modules.each { dirName ->
                            dir(dirName) {
                                sh '''
                                terraform init || true
                                terraform destroy -auto-approve || true
                                '''
                            }
                        }
                    }
                }
            }
        }
        stage('Destroy ECR Repository') {
            steps {
                dir('ecr_repository') {
                    sh '''
                        terraform init
                        terraform destroy -auto-approve
                    '''
                }
            }
        }
        stage('Create ECR Repository - Plan') {
            steps {
                dir('ecr_repository') {
                    sh 'terraform init'
                    sh 'terraform plan'
                }
            }
        }
        stage('Create ECR Repository - Apply') {
            steps {
                withCredentials([aws(credentialsId: 'aws_credentials')]) {
                    dir('ecr_repository') {
                        sh 'terraform apply -auto-approve'
                        echo 'An ECR repo was just created in your AWS account.'
                    }
                }
            }
        }
        stage('Get Terraform Outputs') {
            steps {
                dir('ecr_repository') {
                    script {
                        try {
                            // Get raw JSON string from Terraform
                            def outputJson = sh(script: 'terraform output -json', returnStdout: true).trim()
                            echo "Raw output from terraform: ${outputJson}"

                            // Parse JSON string into a map
                            def outputs = new groovy.json.JsonSlurper().parseText(outputJson)

                            // Extract the ECR repository URL
                            def ecrRepo = outputs['django_ecr_repo_url']['value']
                            echo "Parsed ECR Repo: ${ecrRepo}"

                            // Save it to environment variable
                            env.ECR_REPO = ecrRepo
                        } catch (err) {
                            echo "Error while reading terraform output: ${err}"
                            currentBuild.result = 'FAILURE'
                            error("Stopping pipeline due to terraform output failure.")
                        }
                    }
                }
            }
        }
        stage('Create A Django Docker Image') {
            steps {
                dir('Django') {
                    withCredentials([aws(credentialsId: 'aws_credentials')]) {
                        sh '''
                        ECR_REPO=${ECR_REPO}

                        echo "ECR Repository:  $ECR_REPO"
                        echo "Logging into ECR..."
                        aws ecr get-login-password --region ap-south-1 | docker login --username AWS --password-stdin  $ECR_REPO

                        echo "Building Docker image..."
                        docker build -t django-service:latest .

                        echo "Tagging image with ECR repo..."
                        docker tag django-service:latest  $ECR_REPO:latest

                        echo "Pushing image to ECR..."
                        docker push  $ECR_REPO:latest
                        '''
                    }
                }
            }
        }
        stage('Terraform Destroy Previous') {
            steps {
                dir('infrastructure') {
                    withCredentials([aws(credentialsId: 'aws_credentials')]) {
                        sh 'terraform init'
                        sh 'terraform destroy -auto-approve'
                    }
                }
            }
        }
        stage('Build Infrastructure') {
            steps {
                dir('infrastructure') {
                    withCredentials([aws(credentialsId: 'aws_credentials')]) {
                        sh 'terraform init'
                        sh 'terraform apply -auto-approve'
                    }
                }
            }
        }
        stage('Terraform Apply ECS') {
            steps {
                dir('ecs_cluster') {
                    withCredentials([aws(credentialsId: 'aws_credentials')]) {
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
                def folders = ['infrastructure', 'terraform/ecs_cluster', 'ecr_repository']

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

Attached are the Terraform state files and build.log file for your reference.

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
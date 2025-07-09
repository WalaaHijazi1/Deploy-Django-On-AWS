pipeline {
    agent any
    environment {
        bucketName = 'django-terraform-state-files'
        region     = 'ap-south-1'
    }
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
        stage('Check And Create Bucket'){
            steps{
                withCredentials([aws(credentialsId: 'aws-credentials')]) {
                    def checkCommand = "aws s3api head-bucket --bucket ${bucketName}"
                    def bucketExists = sh (script: "${checkCommand}", returnStatus : true ) == 0

                    if (bucketExists) {
                        echo "s3 bucket does exist with terraform state in it!"
                    }
                    else {
                        echo "s3 bucket does not exist, a new one will be created!"
                        sh "aws s3api create-bucket --bucket ${bucketName} --region ${region} --create-bucket-configuration LocationConstraint=${region}"
                        echo "s3 buckket is created in region ap-south-1 under the name ${bucketName}"
                    }

                    // Write the bucket name into a .tfvars file for Terraform

                    writeFile file: 'env.auto.tfvars', text: """
                    bucket_name = "${bucketName}"
                    region      = "${region}"
                    """
                }
            }
        }
        stage('Create/Check ECR Repository') {
            steps {
                dir('ecr_repository') {
                    withCredentials([aws(credentialsId: 'aws_credentials')]) {
                        script{
                            sh """
                                terraform init \\
                                    -backend-config=\"bucket=${bucketName}\" \\
                                    -backend-config=\"key=infra/terraform.tfstate\" \\
                                    -backend-config=\"region=${region}\" \\
                                    -backend-config=\"encrypt=true\"
                            """

                            // Check the tf.state file in the backend -s3 bucket
                            def exitCode = sh(
                                script: "terraform plan -detailed-exitcode",
                                returnStatus: true
                            )

                            if (exitCode == 2) {
                                echo "Changes detected - applying ECR changes"
                                sh "terraform apply -auto-approve"
                            } else if (exitCode == 0) {
                                echo "No changes detected - skipping apply."
                            } else {
                                error("Terraform plan failed with exit code ${exitCode}")
                            }
                        }
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
                        sh """
                        ECR_REPO=${ECR_REPO}

                        echo "ECR Repository:  ${ECR_REPO}"
                        echo "Logging into ECR..."
                        aws ecr get-login-password --region ${region} | docker login --username AWS --password-stdin  ${ECR_REPO}

                        echo "Building Docker image..."
                        docker build -t django-service:latest .

                        echo "Tagging image with ECR repo..."
                        docker tag django-service:latest  ${ECR_REPO}:latest

                        echo "Pushing image to ECR..."
                        docker push  ${ECR_REPO}:latest
                        """
                    }
                }
            }
        }
        stage('Terraform Apply ECS') {
            steps {
                dir('ecs_cluster') {
                    withCredentials([aws(credentialsId: 'aws_credentials')]) {
                        script {
                            // Init and Import
                            sh """
                                terraform init \\
                                    -backend-config="bucket=${bucketName}" \\
                                    -backend-config="key=infra/terraform.tfstate" \\
                                    -backend-config="region=${region}" \\
                                    -backend-config="encrypt=true"

                                terraform import aws_iam_role.ecs_task_execution_role ecsTaskExecutionRole || true
                            """

                            // Run plan and capture exit code
                            def exitCode = sh(
                                script: "terraform plan -detailed-exitcode -var=\"ecr_repo_url=${env.ECR_REPO}\"",
                                returnStatus: true
                            )

                            if (exitCode == 2) {
                                echo "Changes detected — applying infrastructure..."
                                sh "terraform apply -auto-approve -var=\"ecr_repo_url=${env.ECR_REPO}\""
                            } else if (exitCode == 0) {
                                echo "No changes detected — skipping apply."
                            } else {
                                error("Terraform plan failed with exit code ${exitCode}")
                            }
                        }
                    }
                }
            }
        }
    }

    post {
        always {
            script {
                def attachments = []
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
pipeline {
    agent any

    environment {
        AWS_REGION     = 'us-east-1'
        TF_IN_AUTOMATION = 'true'
        TF_INPUT         = '0'
        TF_CLI_ARGS      = '-no-color'
    }

    stages {

        // -----------------------------------------------------------------
        // 1. SET AWS CREDENTIALS
        // Verify stored IAM credential binding works before touching infra.
        // -----------------------------------------------------------------
        stage('Set AWS Credentials') {
            steps {
                withCredentials([[
                    $class: 'AmazonWebServicesCredentialsBinding',
                    credentialsId: 'JenkinsTest01'
                ]]) {
                    sh 'aws sts get-caller-identity'
                }
            }
        }

        // -----------------------------------------------------------------
        // 2. S3 ARTIFACT TEST
        // Upload a test file, verify round-trip download, then clean up.
        // Proves the IAM credential has s3:PutObject / s3:GetObject.
        // -----------------------------------------------------------------
        stage('S3 Artifact Test') {
            steps {
                withCredentials([[
                    $class: 'AmazonWebServicesCredentialsBinding',
                    credentialsId: 'JenkinsTest01'
                ]]) {
                    sh '''
                        echo "Build ${BUILD_NUMBER} artifact - $(date -u)" > test-artifact.txt

                        echo "--- Uploading ---"
                        aws s3 cp test-artifact.txt \
                            s3://class7-armagaggeon-tf-bucket/jenkins-artifacts/test-artifact-${BUILD_NUMBER}.txt

                        echo "--- Downloading ---"
                        aws s3 cp \
                            s3://class7-armagaggeon-tf-bucket/jenkins-artifacts/test-artifact-${BUILD_NUMBER}.txt \
                            downloaded-artifact.txt

                        echo "--- Verifying ---"
                        diff test-artifact.txt downloaded-artifact.txt \
                            && echo "S3 ARTIFACT TEST PASSED"

                        echo "--- Cleaning up ---"
                        aws s3 rm \
                            s3://class7-armagaggeon-tf-bucket/jenkins-artifacts/test-artifact-${BUILD_NUMBER}.txt
                    '''
                }
            }
        }

        // -----------------------------------------------------------------
        // 3. TERRAFORM INIT
        // -----------------------------------------------------------------
        stage('TF Init') {
            steps {
                withCredentials([[
                    $class: 'AmazonWebServicesCredentialsBinding',
                    credentialsId: 'JenkinsTest01'
                ]]) {
                    sh 'terraform init -reconfigure'
                }
            }
        }

        // -----------------------------------------------------------------
        // 4. PIKE SCAN
        // Outputs the minimum IAM policy required for this TF code.
        // Non-blocking (|| true) — never kills the pipeline.
        // -----------------------------------------------------------------
        stage('Pike Scan') {
            steps {
                sh '''
                    docker run --rm \
                        --volume "${WORKSPACE}:/tf" \
                        jameswoolfenden/pike scan -d /tf -o json \
                        > pike-policy.json 2>&1 || true
                    echo "=== Pike Minimum IAM Policy ==="
                    cat pike-policy.json
                '''
                archiveArtifacts artifacts: 'pike-policy.json', allowEmptyArchive: true
            }
        }

        // -----------------------------------------------------------------
        // 5. TERRAFORM PLAN
        // -----------------------------------------------------------------
        stage('TF Plan') {
            steps {
                withCredentials([[
                    $class: 'AmazonWebServicesCredentialsBinding',
                    credentialsId: 'JenkinsTest01'
                ]]) {
                    sh 'terraform plan -out=tfplan'
                }
            }
        }

        // -----------------------------------------------------------------
        // 6. TERRAFORM APPLY
        // Human gate — review plan before any bucket is created.
        // -----------------------------------------------------------------
        stage('TF Apply') {
            steps {
                input message: 'Review the plan above. Proceed to create the S3 bucket?', ok: 'Deploy'
                withCredentials([[
                    $class: 'AmazonWebServicesCredentialsBinding',
                    credentialsId: 'JenkinsTest01'
                ]]) {
                    sh 'terraform apply -auto-approve tfplan'
                }
            }
        }

        // -----------------------------------------------------------------
        // 7. TERRAFORM DESTROY
        // Human gate — explicit approval required to tear down.
        // -----------------------------------------------------------------
        stage('TF Destroy') {
            steps {
                input message: 'Destroy the S3 bucket created by this run?', ok: 'Destroy'
                withCredentials([[
                    $class: 'AmazonWebServicesCredentialsBinding',
                    credentialsId: 'JenkinsTest01'
                ]]) {
                    sh 'terraform destroy -auto-approve'
                }
            }
        }
    }

    post {
        success {
            echo 'Pipeline completed successfully.'
        }
        failure {
            echo 'Pipeline failed — check stage logs above.'
        }
    }
}

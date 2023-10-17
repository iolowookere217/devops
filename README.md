## Automate the deployment of a simple web app on aws resources from a circleci pipeline

# circleci pipeline -----> config.yml file

---

#### version of circleci

    version: 2.1

    orbs:
    sam: circleci/aws-sam-serverless@3.1.0

#### if an error occurs and unable to complete the pipeline process, this step helps to clean up the environment by destroying the created clusters

    commands:
    destroy-cluster:
    description: Destroy EKS Cluster.
    steps: - run:
    name: Destroy environments
    when: on_fail
    command: |
    eksctl delete cluster --name devopsproject

#### This step installs kubectl and eksctl on the system by downloading the necessary binaries, setting permissions, and adding them to the system's PATH for easy access.

    install-kubectl-and-eksctl:
    description: install kubectl and eksctl
    steps: - run:
    name: Installing kubectl and eksctl
    command: |
    yum install tar gzip -y
    curl --silent --location -o /usr/local/bin/kubectl https://amazon-eks.s3.us-west-2.amazonaws.com/1.21.2/2021-07-05/bin/linux/amd64/kubectl
    chmod +x /usr/local/bin/kubectl
    mkdir -p $HOME/bin && cp ./kubectl $HOME/bin/kubectl && export PATH=$PATH:$HOME/bin
    curl --silent --location "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz" | tar xz -C /tmp
    mv /tmp/eksctl /usr/local/bin
    eksctl version

#### This job, 'lint-app,' uses a Python 3.8 Docker container to perform linting on the 'myapp.py' file using 'flake8' after upgrading pip and installing 'flake8'.

    jobs:
    lint-app:
    docker: - image: python:3.8
    steps: - checkout - run:
    name: Pythdon linting
    command: |
    pip install --upgrade pip
    pip install flake8
    flake8 myapp.py

#### In the 'build-and-push-node1' step, a dedicated machine is used. It checks out the code, loads environment variables from 'DOTENV_FILE' into '.env,' builds a Docker image tagged 'iolowookere217/my-webapp:v1,' and pushes it to a container registry after logging in.

    build-and-push-node1:
    machine: true
    steps:
      - checkout
      - run:
          name: Load .env File
          command: |
            echo "$DOTENV_FILE" > .env
      - run:
          name: Build and Push Docker Image for deploy
          command: |
            docker build -t iolowookere217/my-webapp:v1 .
            echo "$DOTENV_FILE" | docker login -u iolowookere217 --password-stdin
            docker push iolowookere217/my-webapp:v1

#### This step, 'delete-existing-create-new-ec2-resources,' uses an Amazon AWS CLI Docker container. It first delete the existing stack named 'devops-stack' and then configures AWS credentials, then creates EC2 resources by launching a CloudFormation stack named 'devops-stack' using a template file ('cf.yml') in the 'us-east-1' region, and waits for the stack creation to complete. the environment variable are set in circle ci.

    delete-existing-create-new-ec2-resources:
    docker:
    - image: amazon/aws-cli
    steps:
    - checkout
    - run:
        name: Configure AWS Credentials
        command: |
          aws cloudformation delete-stack --stack-name devops-stack --region us-east-1
          aws cloudformation wait stack-delete-complete --stack-name devops-stack --region us-east-1
          aws configure set aws_access_key_id $AWS_ACCESS_KEY_ID
          aws configure set aws_secret_access_key $AWS_SECRET_ACCESS_KEY
          aws configure set default.region us-east-1
    - run:
        name: Creating EC2 resources
        command: |
          aws cloudformation create-stack \
            --stack-name devops-stack \
            --template-body file://cf.yml \
            --region us-east-1
          aws cloudformation wait stack-create-complete --stack-name devops-stack --region us-east-1

#### This 'delete-existing-create-new-eks-cluster-app' step, employing an Amazon AWS CLI Docker container, first deletes existing kubernetes cluster named 'devopsproject' and then creates a new Kubernetes cluster called 'devopsproject' in the 'us-east-1' region. It verifies the node status, establishes a Kubernetes namespace named 'node-namespace,' updates the 'kubeconfig' for 'devopsproject,' and deploys version 1 of an application ('deploy.yml'). Finally, it references the 'destroy-cluster' step.

    delete-existing-create-new-eks-cluster-app:
        docker:
          - image: amazon/aws-cli
        steps:
          - checkout
          - install-kubectl-and-eksctl
          - run:
              name: Creating K8S cluster
              command: |
                echo
                eksctl delete cluster --name devopsproject --region us-east-1 --wait
                eksctl create cluster \
                --name devopsproject \
                --region us-east-1 \
                # --with-oidc \
                # --ssh-access \
                # --ssh-public-key new-key
                kubectl get nodes -o wide
                kubectl create namespace node-namespace
                aws eks update-kubeconfig --name devopsproject --region us-east-1
          - run:
              name: Deploying v1
              command: |
                kubectl apply -f deploy.yml
          - destroy-cluster

#### 'smoke-test-v1' step, using an Amazon AWS CLI Docker container, installs dependencies, including 'jq,' and references the 'destroy-cluster' step.

    smoke-test-v1:
    docker: - image: amazon/aws-cli
    steps: - checkout - install-kubectl-and-eksctl - run:
    name: Installing dependencies
    command: |
    echo
    yum install jq -y - destroy-cluster

#### In the 'the_jobs' workflow: 'lint-app' job runs first. 'smoke-test-v1' and 'build-and-push-node1' jobs run in parallel after 'lint-app. 'delete-existing-ec2-resources' follows 'build-and-push-node1.' 'create-ec2-resources-after-deletion' runs after 'delete-existing-ec2-resources.'Finally, 'create-eks-cluster-app' executes after 'create-ec2-resources-after-deletion,' with dependencies specified accordingly."

    workflows:
    the_jobs:
    jobs: - lint-app - smoke-test-v1:
    requires: [lint-app] - build-and-push-node1:
    requires: [lint-app] - delete-existing-ec2-resources:
    requires: [build-and-push-node1] - create-ec2-resources-after-deletion:
    requires: [delete-existing-ec2-resources] - create-eks-cluster-app:
    requires: [create-ec2-resources-after-deletion]

# Infrastructure as Code (IaC) -----> cf.yml

---

"IaC Infrastructure as a Code (IaC) simplifies infrastructure management by using code to create configuration files that define infrastructure specifications, enabling easier editing and distribution of configurations."

Here, I defined the infrastructure specifications in the cf.yml file.

#### create a cloud account and ssh access for the instance

- 1. Create an AWS account
- 2. Create an IAM user account select the programmatic option
- 3. Create a key pair

#### create the t2-micro EC2 Instance in the us-east-1 region on AWS

    Resources:
    WebAppInstance:
    Type: AWS::EC2::Instance
    Properties:
    ImageId: ami-0d5eff06f840b45e9 # Ubuntu ImageID valid only in us-east-1 region. You can use the ImageId locator https://cloud-images.ubuntu.com/locator/ec2/
    InstanceType: t2.micro
    KeyName: new-key # <------your key-pair name
    SecurityGroupIds: - !Ref WebAppSecurityGroup

#### A security group resource that allows traffic in, on port 22 for SSH and ports 80 and 443 for HTTP and HTTPS traffic.

    WebAppSecurityGroup:
    Type: AWS::EC2::SecurityGroup
    Properties:
    GroupName: !Join ["-", [webapp-security-group, dev]]
    GroupDescription: "Allow HTTP/HTTPS and SSH inbound and outbound traffic"
    SecurityGroupIngress: - IpProtocol: tcp
    FromPort: 80
    ToPort: 80
    CidrIp: 0.0.0.0/0 - IpProtocol: tcp
    FromPort: 443
    ToPort: 443
    CidrIp: 0.0.0.0/0 - IpProtocol: tcp
    FromPort: 22
    ToPort: 22
    CidrIp: 0.0.0.0/0

## assign an elastic IP address to Instance

    WebAppEIP:
    Type: AWS::EC2::EIP
    Properties:
    Domain: vpc
    InstanceId: !Ref WebAppInstance
    Tags: - Key: Name
    Value: !Join ["-", [webapp-eip, dev]]
    Outputs:
    WebsiteURL:
    Value: !Sub http://${WebAppEIP}
    Description: WebApp URL

# Deployments and services -----> deploy.yml file

---

## Deployment (node-app-deployment):

#### Deploys an application named 'node-app' with three replicas. Applies node affinity, ensuring it runs on nodes with specified architectures (amd64 or arm64). Pulls the 'iolowookere217/my-webapp:v1' image and exposes it on port 5000.

        apiVersion: apps/v1
        kind: Deployment
        metadata:
        name: node-app-deployment
        namespace: node-namespace
        labels:
        app: node-label
        spec:
        replicas: 3
        selector:
        matchLabels:
        app: node-label
        template:
        metadata:
        labels:
        app: node-label
        spec:
        affinity:
        nodeAffinity:
        requiredDuringSchedulingIgnoredDuringExecution:
        nodeSelectorTerms: - matchExpressions: - key: kubernetes.io/arch
        operator: In
        values: - amd64 - arm64
        containers: - name: node-app
        image: iolowookere217/my-webapp:v1
        ports: - name: tcp
        containerPort: 5000
        imagePullPolicy: Always

## Service (node-service):

#### Exposes the 'node-label' application as a LoadBalancer service on port 5000 within the 'node-namespace.' Routes traffic to pods labeled with 'app: node-label.'

        apiVersion: v1
        kind: Service
        metadata:
        name: node-service
        namespace: node-namespace
        labels:
        app: node-label
        spec:
        selector:
        app: node-label
        type: LoadBalancer
        ports: - protocol: TCP
        port: 5000
        targetPort: 5000

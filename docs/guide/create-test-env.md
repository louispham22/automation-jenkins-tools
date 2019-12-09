# rro

## Directions

1. Change the Default Profile to correct AWS environment

    `export AWS_DEFAULT_PROFILE=testenvname`

1. Create Environment

    (in `prepare/aws-test-env`)

    `./create-test-env.sh`

1. Create Jenkins Credentials

    (in `prepare/aws-test-env`)

    `./create-userkey.sh`

1. Create Docker CA

    (in `prepare/aws-test-env`)

    `./docker-ca.sh`

1. Register Cloudwatch Agent Configs

    (in `prepare/aws-test-env`)

    `./cloudwatch-agent.sh`

1. Add credentials to Jenkins

    - Add Credential Scope ([[Credentials]]->[[System]]->[[Add Scope]])
        + The name format should be `AWS AutoTest <project>`
    - Add Credential to Score
        + The ID format should be `AWS-AutoTest-<project>`

1. Create Base Slave AMI

    Execute [Jenkins Job (Automation_BuildAMI_SlaveBase_CreateAMI_Init)](http://jenkins-hrbc.ps.porters.local/view/Automation/job/Automation_BuildAMI_SlaveBase_CreateAMI_Init) with new credentials.

1. Create Control Slave Jenkins Cloud

    [[Manage Jenkins]] -> [[Configure System]] -> [[Add a new cloud]] -> [[Amazon EC2]]

    Name Format: `AWS-AutoTest-<project>`

    Add contents of `AutoTest.jenkins.pem` generated earlier as Key Pair Private Key content.

1. Add Control Slave AMI to Cloud

    Description
    : `AutoTest - <project> - Control`

    AMI ID
    : ID of generated AMI in previous step

    Instance Type
    : `t3.nano` (or `t2.nano`)

    Security Group Names
    : `AutoTest-ControlSlave`

    Remote User
    : `ec2-user`

    Labels
    : `aws-autotest-<project>-control`

    Advanced
    :   Click advance and add the following info:

        - Set Subnet ID (you get this from CloudFormation Output)
        - Profile Id - AutoTest-ControlSlave (you get this from CloudFormation Output)
        - Set 'Connect using Public IP' to `true`
        - Set 'Delete root device on instance termination' to `true`
        - Set 'Number of Executors' to `2`

1. Create other AMIs

    Use the following Jenkins Jobs to create the rest of the slave AMIs.

    - Automation_BuildAMI_DockerServer_Prepare
    - Automation_BuildAMI_DockerServer_CreateAMI
    - Automation_BuildAMI_TestRunner_Prepare
    - Automation_BuildAMI_TestRunner_CreateAMI

1. Register Docker AMI

    You must specify the version of the docker server AMI you wish to use.

    `./register-ami.sh -d 0.2.0`

1. Add Test Runner Slave AMI to Cloud

    Description
    : `AutoTest - <project> - TestRunner`

    AMI ID
    : ID of generated AMI in previous step

    Instance Type
    : `t3.medium` (or `t2.medium`)

    Security Group Names
    : `AutoTest-ControlSlave`

    Remote User
    : `ec2-user`

    Labels
    : `aws-autotest-<project>-runner`

    Advanced
    :   Click advance and add the following info:

        - Set Subnet ID (you get this from CloudFormation Output)
        - Profile Id - AutoTest-TestRunner (you get this from CloudFormation Output)
        - Set 'Connect using Public IP' to `true`
        - Set 'Delete root device on instance termination' to `true`
        - Set 'Number of Executors' to `1`

1. Add ReportGenerator Slave AMI to Cloud

    Description
    : `AutoTest - <project> - ReportGenerator`

    AMI ID
    : ID of generated AMI in previous step (use Test Runner AMI)

    Instance Type
    : `r5.large` (or `r4.large`)

    Security Group Names
    : `AutoTest-ControlSlave`

    Remote User
    : `ec2-user`

    Labels
    : `aws-autotest-<project>-report`

    Advanced
    :   Click advance and add the following info:

        - Set Subnet ID (you get this from CloudFormation Output)
        - Profile Id - AutoTest-TestRunner (you get this from CloudFormation Output)
        - Set 'Connect using Public IP' to `true`
        - Set 'Delete root device on instance termination' to `true`
        - Set 'Number of Executors' to `1`
        - Set JVM Options to `-Dhudson.slaves.ChannelPinger.pingTimeoutSeconds=600 -Xmx15G`

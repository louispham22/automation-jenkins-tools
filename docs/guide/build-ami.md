---
title: Building AWS AMI
---
# Building AWS AMI

::: header lang-en

| Product | AWS Automation   |
| ------- | ---------------- |
| Author  | Arwyn Hainsworth |
| Status  | 1.0              |

[[TOC]]

:::

## Overview

Building Amazon Machine Images (AMI) is a relatively simple task, but the lack of a standard method for doing so can cause unexpected complexities.

In essence all that is needed is to start up a base AMI, install software and create an AMI from the new setup.

There are a number of tools that can do this task, such as Chef and Packer, but these tools have additional features and add unneeded complexity.

The following guide uses 2 bash scripts that were developed with a single task in mind - creating Linux AMIs.

In addition to giving an overview of the build process, it will also give an introduction to composing images and an instances life-cycle. You need to have an understanding of these processes in order to integrate your application into the instance life-cycle.

## Build Process

During the build process, an instance from a base AMI will be started with user-data that installs software, applies a tarball with the additions to the root fs, then shuts down the instance. When the instance is shutdown, an AMI will be created and the instance is terminated.

SSH is not used at any point and a connection from the build server to the instance is not required.

The user-data contains a [cloud-init][cloud-init][^cloud-init] script. Cloud init is not an Amazon technology (although it is present in all Amazon images) and in theory, the same script could work on other cloud systems (This has not been tested).

The build process is separated into 2 clear phases.

### Phase 1: Compiling Cloud-Init User-Data

This phase needs the following:

1. Access to the AMI `source` directory.

During this phase, the `build/compile-create-ami-userdata.sh` script will do the following:

1. Prepare a directory that contains all cloud-init YML configuration files.
1. Prepare a directory that contains the additions the root file system.
1. (Optional) Runs a bash script in the context of the work directory
1. (Optional) Copies a bash script to the root file system directory and adds a script to run, then delete it to the cloud-init directory.
1. (Optional) Creates a tar of the filesystem directory and adds a cloud-init script to extract it.
1. Merge all cloud-init configuration files and compress.

Cloud-init data is limited to 16kb. If the filesystem, when tarred and compressed is less than 8Kb, then it will be included in the cloud-init used data. If it exceeds this size, then it needs to be made available for download.

Please refer to [compile-create-ami-userdata.sh documentation][build-compile-userdata] for further details on storage systems and `source` directory layout.

!!! warning Important

    This phase does not have access to the cloud and does not include uploading the filesystem to a storage system (such as S3), but it does need to know the exact location the filesystem tarball will be uploaded to.

    If a storage system is needed, the compile script will provide the filesystem tarball as part of its output.

### Phase 2: Building the AMI

This phase needs the following:

1. Access to AWS.
    1. Create, Modify, Terminate and Describe EC2 Instance
    1. Create and Describe EC2 AMI
    1. (Optional) Upload to S3
1. The compiled user-data
1. (Optional) The compiled filesystem tarball
1. (Optional) Variables used/generated during compilation (E.G. S3 URL the tarball needs to be uploaded to.)

During this phase, the `build/build-ami.sh` script will do the following:

1. (Optional) Upload filesystem tarball to S3
1. Create EC2 Instance with userdata attached
1. Wait for EC2 Instance to terminate
1. Create AMI from Instance
1. Wait for AMI Creation to complete
1. Terminate EC2 Instance

The tarball is not deleted from S3. Please use the S3 life-cycle settings to ensure the file is removed.

Please refer to [build-ami.sh documentation][build-ami] for further details.

## Composing Images

An EC2 Instance is created from an AMI. This AMI contains:

- A FileSystem
    + This contains configuration files and installed software
    + It also contains cloud-init configuration files (in `/etc/cloud/cloud.cfg.d`)

When you start an instance, you may also provide userdata, which can include cloud-init configuration files. These configuration files are merged with the ones included in the AMI before being executed.

The user-data cloud-init scripts are what the build process uses to prepare the instance for AMI creation. You can also use cloud-init scripts to control what happens when an instance is started from your AMI by adding scripts to the filesystem of your AMI.

A simple example of cloud-init usage is in the [jenkins slave ami][repo-slave-base][^repo-slave-base] which uses cloud-init to:

1. prevent unexpected software updates
1. update the `jenkins` user ssh public key.

These steps are done during each instance startup from the created AMI. They are not run during the AMI Creation.

Cloud-init can also be used to format and mount file-systems, a task that cannot be done during AMI creation, since the disks will be created for each new instance.

However cloud-init scripts will only be run once per instance. They will not run every time the instance is restarted. For this you need to create or modify the `systemd` services.

### Instance Life-Cycle

::: comparison

!!! info EC2 Instance life-cycle

    ![Instance Life-Cycle][img-instance-lifecycle]

    ---

    Source: [AWS EC2 Instance Lifecycle][aws-instance-lifecycle][^aws-instance-lifecycle]

!!! info Instance state
    | Instance state | Description |
    | -------------- | --- |
    | pending        | The instance is preparing to enter the running state. An instance enters the pending state when it launches for the first time, or when it is restarted after being in the stopped state. |
    | running        | The instance is running and ready for use. |
    | stopping       | The instance is preparing to be stopped or stop-hibernated. |
    | stopped        | The instance is shut down and cannot be used. The instance can be restarted at any time. |
    | shutting-down  | The instance is preparing to be terminated. |
    | terminated     | The instance has been permanently deleted and cannot be restarted. |
:::

The cloud-init scripts will be run the _first_ time the instance enters the running state. The enabled services will be started and stopped each time the instance is started and stopped.

### Service Life-Cycle

Most modern linux systems use `systemd` for service life-cycle management. `systemd` is complicated and too large to give a detailed overview here. Please refer to the following guides for more help on the subject:

- [Understanding Systemd Units and Unit Files][systemd-help1][^systemd-help1]

Essentially creating services involves creating a `unit`, which is a configuration file that defines the service. This unit can now be started/stopped or enabled (starts on instance startup). You can also append sections to an existing unit by placing the configuration file in a directory named after the existing service.

A simple example of appending to existing services is in the [jenkins slave ami][repo-slave-base][^repo-slave-base]. It appends the `ExecPre` stanza to `amazon-cloudwatch-agent` service to fetch the configuration file from the AWS parameter store before the service starts up.

## Usage and Examples

Like most of the script in this repository, these tools are designed to run from jenkins.

Please Jenkins Jobs and repositories are use to build the test infrastructure AMIs. You can use them as examples of how you can use these scripts:

// TODO link to jenkins

Gerrit Repository for [Test infrastructure AMIs][repo-slave-base].

[cloud-init]: https://cloudinit.readthedocs.io/en/latest/
[^cloud-init]: [cloud-init documentation][cloud-init]

[systemd-help1]: https://www.digitalocean.com/community/tutorials/understanding-systemd-units-and-unit-files
[^systemd-help1]: [Understanding Systemd Units and Unit Files][systemd-help1]

[aws-instance-lifecycle]: https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-instance-lifecycle.html
[^aws-instance-lifecycle]: [AWS EC2 Instance Lifecycle][aws-instance-lifecycle]

[repo-slave-base]: http://gerrit.ps.porters.local/automation/jenkins/ami
[^repo-slave-base]: Gerrit Repository for [Jenkins Slave AMI][repo-slave-base]

[build-ami]: ../build/build-ami.md
[build-compile-userdata]: ../build/compile-create-ami-userdata.md

[img-instance-lifecycle]: https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/images/instance_lifecycle.png

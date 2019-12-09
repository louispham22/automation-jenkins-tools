---
title: Manual for build/compile-create-ami-userdata.sh
---
# Manual for `build/compile-create-ami-userdata.sh`

::: header lang-en

| Product | AWS Automation   |
| ------- | ---------------- |
| Author  | Arwyn Hainsworth |
| Status  | 1.0              |

[[TOC]]

:::

## Name

compile-create-ami-userdata.sh - compiles userdata to create an AMI

## Synopsis

`compile-create-ami-userdata.sh` source target

## Details

The `compile-create-ami-userdata` script will take the `source` and generate 1~3 output files in the `target` directory.

1. `userdata.gz` - the compiled, compressed userdata
1. `fs.tgz` - if the filesystem was too large to fit in userdata, this will be left in the target directory.
1. `vars.env` - Bash environment variables used or generated during compilation.

## Options

`source`
:   The path the AMI source. See the description of expected structure below.

`target`
:   Target directory to write output files to.

## Environment Variables

`AWSREGION`
:   (Optional) AWS Region. Defaults to `ap-northeast-1`.

`S3URL`
:   (Required if S3 storage is needed) The S3 URL the `fs.tgz` will be uploaded to and can be download during AMI build.

    Should be in the `s3://<bucket>/path/to/fs.tgz` format.

## Source Directory Structure

## External Storage

When the filesystem is larger than 8kb, then external storage is required to transfer the tarball.

Currently only S3 is supported. The `S3URL` environment variable must contain the full path where the `fs.tgz` file will be uploaded to and available as.

## vars.env


ec2-snapshot-backup
===================

This simple bash script does Amazon EBS volume backup from Tag "Name". Its suitable for environments where EBS volumes are properly tagged and backup on multiple EBS volumes instead of specifying Volume ID.
You can also use this script for disaster recovery setup.

## Requirements
* Amazon EC2 CLI tool
* openjdk-6-jdk
* AWS Access key

## Usage

```
Usage: ec2-snapshot-backup [OPTION]...
  -t,    --tagprefix   The AWS Tag Name, Default is Empty

  -n,    --number      The maximum number of snapshots to be left
               
  -dn,   --dnumber     The maximum number of snapshots to be left at the DR

  -cr,   --cregion     The current region to backup the EBS volume, Default is ${CREGION}

  -dr,   --dregion     The destination region to backup the EBS volume, Default is to ${DREGION}

  -b,    --backup-day  The day of the week to backup the EBS volume to DR region.
               
  -h,    --help        Display help file
 
```

**Without** Copying to Disaster Recovery Region

```
~:$ ec2-snapshot-backup -t web -n 2 -cr ap-southeast-1
```

**With** Copying to Disaster Recovery Region

```
~:$ ec2-snapshot-backup -t web -n 2 -cr ap-southeast-1 -dr eu-west-1 -b Sunday -dn 3
```

# Studio Link

## Current Base Images

### BeagleBone Black

http://archlinuxarm.org/platforms/armv7/ti/beaglebone-black

## Bootstrap

If you have a clean archlinux image you can run one of the following commands:

### Install/Update stable

```
touch /etc/studio-link-community
curl -L https://raw.githubusercontent.com/studio-connect/images/14.5.0-alpha/bootstrap.sh | bash
```

### Install/Update development

```
touch /etc/studio-link-community
curl -L https://raw.githubusercontent.com/studio-connect/images/master/bootstrap.sh | bash
```

### Install/Update a specific branche

```
touch /etc/studio-link-community
curl -L https://raw.githubusercontent.com/studio-connect/images/feature_branch/bootstrap.sh | bash
```

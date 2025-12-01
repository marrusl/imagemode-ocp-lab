#!/usr/bin/env bash

# Write the sample MachineOSConfig to a YAML file:
cat << EOF > my-machineosconfig.yaml
---
apiVersion: machineconfiguration.openshift.io/v1
kind: MachineOSConfig
metadata:
  name: master
spec:
  # Here is where you refer to the MachineConfigPool that you want your built
  # image to be deployed to.
  machineConfigPool:
    name: master
  containerFile:
  - content: |-
      <containerfile contents>
  # Here is where you can select an image builder type. For now, we only
  # support the "Job" type that we maintain ourselves. Future
  # integrations can / will include other build system integrations.
  imageBuilder:
    imageBuilderType: Job
  # Here is where you specify the name of the push secret you use to push
  # your newly-built image to.
  renderedImagePushSecret:
    name: <secret-name>
  # Here is where you specify the image registry to push your newly-built
  # images to.
  renderedImagePushSpec: <final image pullspec>
EOF

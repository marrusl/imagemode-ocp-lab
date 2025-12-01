# Image mode on OpenShift Lab

# Requirements

Physical or virtual machine with two disks  
Disk A → 120gb  
Disk B → Enough to store your images

RAM: 8gb min (16 suggested)  
vCPUs: 8

Internet connected cluster


# SNO installation via Assisted Installer

Login to console  
In the Red Hat OpenShift box click create cluster  
![Assisted Installer](https://raw.githubusercontent.com/marrusl/imagemode-ocp-lab/refs/heads/main/images/SNO-via-Assisted.png)  

Then “Datacenter”  
Then under Assisted Installer, click Create Cluster  

![Assisted Installer 2](https://raw.githubusercontent.com/marrusl/imagemode-ocp-lab/refs/heads/main/images/SNO-via-Assisted-2.png)

Enter cluster name and domain  
Under “Number of control plane nodes” select 1  

![Select SNO](https://raw.githubusercontent.com/marrusl/imagemode-ocp-lab/refs/heads/main/images/Select-SNO.png)

Next

IF YOU ARE USING THE INTERNAL REGISTRY: Under Operator selection, expand “Single Operators” and under Storage, select “Logical Volume Manager Storage”. NOTE: when this operator is installed during cluster bootstrap it will automatically configure the 2nd drive for use. Do it.

Next

In the Host discovery screen click “Add host”

Generate a discovery ISO

1. Select iso type  
2. Add ssh public key  
3. Add proxy settings if applicable  
4. Click Generate Discovery ISO  
5. Download ISO or copy URL for virtual media via BMC  

Virt-manager / KVM setup instructions

1. Create new machine   
2. Select discovery ISO  
3. Unselect Auto OS detection and choose “Red Hat Enterprise Linux 9.6”  for OCP 4.19-4.21 or RHEL 9.4 for 4.18.  
4. Finish setup and attach secondary storage to the instance  
5. Boot  
6. Wait for host to show up in console and show Ready, then click Next  
7. Storage: double check that the installation disk is the one you intended and click Next  
8. Review networking and click Next  
9. Review installation plan and then click Install cluster  
10. While you are waiting, copy the **kubeadmin** **password** download the **kubeconfig** locally  
11. When the server is finished installing, you can login at **console-openshift-console.apps.YOUR-CLUSTER.DOMAIN**  
12. Or with `oc login --web`

# Enable OpenShift internal registry

For development and test environments, you might use the OpenShift internal registry. It's disabled by default, but it's just fine for our needs here and the easiest way to get started in your lab without external dependencies. For production, consider using your enterprise registry for better manageability and compliance.

Enable route creation for the registry (this can take some time to go live, may as well do it first)

```
oc patch configs.imageregistry.operator.openshift.io/cluster --patch '{"spec":{"defaultRoute":true}}' --type=merge
```

Apply a persistent volume claim for the registry

```
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: registry-claim
  namespace: openshift-image-registry
  annotations:
    imageregistry.openshift.io: "true"
spec:
  accessModes:
  - ReadWriteOnce
  volumeMode: Filesystem
  resources:
    requests:
      storage: 100Gi
  storageClassName: lvms-vg1
```

Configure the operator to use our new claim

```
oc patch configs.imageregistry.operator.openshift.io/cluster --type=merge --patch '{"spec": {"storage":{"pvc":{"claim":"registry-claim"}}}}'
```

Set the rollout strategy to 1 replica for single-node

```
oc patch config.imageregistry.operator.openshift.io/cluster --type=merge -p '{"spec":{"rolloutStrategy":"Recreate","replicas":1}}'
```

Set the managementState to "Managed" to enable the operator and start the registry.

```
oc patch configs.imageregistry.operator.openshift.io/cluster --type=merge --patch '{"spec":{"managementState":"Managed"}}'
```

Check to see if the default route is live

```
oc get route default-route -n openshift-image-registry --template='{{ .spec.host }}'
```

Since we are using the internal registry, we’ll be using an image stream to store our images

```
oc create imagestream os-images -n openshift-machine-config-operator
```

Now we’ll grab the pushSpec

```
oc get imagestream/os-images  -n openshift-machine-config-operator -o=jsonpath='{.status.dockerImageRepository}'
```

Lastly, we'll need the name of the push secret to write new images:

```
oc get secrets -o name -n openshift-machine-config-operator -o=jsonpath='{.items[?(@.metadata.annotations.openshift\.io\/internal-registry-auth-token\.service-account=="builder")].metadata.name}'
```

# Configure on-cluster image mode

Image mode is configured through a new object type called MachineOSConfigs. One for each MachineConfigPool you are targeting. The pool name must match the “metadata” name in your YAML. In a single node scenario, you must use the `master` pool.

The three inputs you need into the file are:

1. The name of the MachineConfigPool you are targeting  
2. Containerfile content  
3. Your registry push secret  
4. Your registry pull spec

We’re going to add `tcpdump` to our nodes. Adding RHEL packages is simple since your subscription is automatically wired up. Here’s the Containerfile content we’ll be using:

```
FROM configs AS final
RUN dnf install -y tcpdump && \
    dnf clean all && \
    bootc container lint
    # NOTE: on 4.18 use `ostree container commit` in place of
    # `bootc container lint`
```

NOTE: the build job is a multi-stage build where `configs` is the base RHCOS image plus machineconfig content and `final` is the image that will be rolled out to the nodes in the pool.

Using the [refresh-sample-image.sh](http://refresh-sample-image.sh) script to write a MachineOSConfig template. NOTE: this one is hardcoded to `master`.

Optionally, we can use `yq` to save us some YAML indentation pain when working with Containerfiles. Although not included in RHEL, yq can be found in [EPEL](https://access.redhat.com/solutions/3358) and on various platforms such as macOS (via Homebrew), Windows, and Fedora. It’s overkill for short and simple Containerfile content but a lifesaver when things get a little more complicated.

NOTE: the push secret and push spec commands below are only valid when working with the internal registry and image streams. Otherwise, provide your external registry information.

```
export containerfileContents="$(cat Containerfile)"

export pushsecret="$(oc get secrets -o name -n openshift-machine-config-operator -o=jsonpath='{.items[?(@.metadata.annotations.openshift\.io\/internal-registry-auth-token\.service-account=="builder")].metadata.name}')"

export pushspec="$(oc get imagestream/os-images -o=jsonpath='{.status.dockerImageRepository}:latest' -n openshift-machine-config-operator)"

yq -i e '.spec.containerFile[0].content = strenv(containerfileContents)' ./my-machineosconfig.yaml
yq -i e '.spec.renderedImagePushSecret.name = strenv(pushsecret)' ./my-machineosconfig.yaml
yq -i e '.spec.renderedImagePushSpec = strenv(pushspec)' ./my-machineosconfig.yaml
```

Now you should have a complete and hopefully valid MachineOSConfig. Let’s apply it\! The build will take a couple of minutes and the system will be rebooted with tcpdump now installed.
# A simple API based application (consul) on k3s running on Amazon AWS EC2 instance
The sole purpose of this project is to demo the DevOPS example involving AWS, Kubernetes (k3s) and deployment of an application (Consul) using Ansible. This will demonstrate and automation of EC2 instance rollout in Amazon AWS using terraform, subsequent deployment of k3s cluster using ansible and using kubernetes resources to deploy a simple single node consul cluster. This also explores the K3S helmchart controller there by deploying an nfs-server-provisioner from a helm chart and used as a default storage class to be consumed by application pods in the sample consul application. You can see all the deployment has been automated from creating an EC2 isntances to the point where you are ready to browse the consul web api call on publicly available URL.

### Prerequisites:
It is assumed you have an access to your AWS console. So get ready with your ACCESS_CODE and SECRET_KEY. The deployment script will import your public key to AWS key-pair. So get or generate your public key as well. Terraform and ansible installation is required before executing this terraform script.
``` 
$ssh=keygen -t rsa -b 2048 
(accept the default)
$wget https://releases.hashicorp.com/terraform/0.11.13/terraform_0.11.13_linux_amd64.zip 
$unzip terraform_0.11.13_linux_amd64.zip
$cp terraform /usr/local/bin/.
$yum install ansible
```

### Installation Steps:
Clone this repo, change the variable.yml default values as needed, or you can also export the environment variable as below. You will need to install the terraform and ansible for this to work. After initializing terraform and running the terraform the output will be displayed at last with your consul url to access.
```  
$git clone https://github.com/rako1980/signalpath.git
```
```
$export ACCESS_KEY=Your_AWS_Access_key
$export SECRET_KEY=You_AWS_Secret_Key
$export PUBLIC_KEY="public key from ~/.ssh/id_rsa.pub"
$cd signalpath
$terraform init
$terraform apply -var access_key=$ACCESS_KEY -var secret_key=$SECRET_KEY -var ssh_rsa_pub="$PUBLIC_KEY"
... (outout ommited) ...
  Enter a value: yes
.. (output ommited)...
Apply complete! Resources: 10 added, 0 changed, 0 destroyed.
```
```
Outputs:

info = UI url: http://x.x.x.x
ip = x.x.x.x
```

#### Consul UI url:
Consul UI url can be accessed at http or https://[instance public ip address]/ui. Wait few minutes for consul pods to complete rollout before successfully accessing the url. If there is an issue you can ssh to ec2 instance:
```
$ssh ec2-user@[public ip address if ec2 instance]
```

### Destroy the AWS resources
```
$terraform destroy -var access_key=$ACCESS_KEY -var secret_key=$SECRET_KEY -var ssh_rsa_pub="$PUBLIC_KEY"
```

## Deployment explanation:
### variable.tf
Defines all the aws infrastructure variables. By default it uses free tier rhel7 linux AMI and t2.micro instance in us-east-2 region.
### main.cf
All major terraform resources are defined in this file. aws_key_pair will create an aws key pair with your public key contents. It will also deploy a new VPC with cidr block 10.0.0.0/16 rather than using AWS default VPC. A new subnet, internet gateway and routing table are created for this VPC. An elastic IP address is reserved to be assigned to EC2 instance. An EC2 instance is created with public IP accessible from internet. A security group that allows port 22 (for ssh to the EC2 instance in case you would need to login to troubleshooti), and HTTP/S port 80 and 443 to access the consul UI.

After the EC2 instance is initialized, a local provisioner populates the inventory file at ./inventory/hosts, and invokes remote exec to patch the OS and install prerequisites of python so that the OS can be configured with ansible. Note the inventory hosts group_vars (./inventory/group_vars/all) that defines the user and ssh private key file to ssh into the server. Ansible uses ssh for a remote execution of the playbook. Finally an ansible playbook provision.yml is invoked that will setup k3s and deploy consul cluster from a helm chart.

### Ansible provision.yml and roles/
> roles/
> - setup_k3s
> - install_consul
 
setup_k3s role installs k3s from the source script located at https://get.k3s.io in a single master/ single node configuration. An nfs provisioner helm chart is deployed to be used as a default dynamic provisioner. Note that k3s also provides a local-path-provisioner yaml config to configure the local storage using host path which is a separate deployment after bringing up k3s cluster. However, the consul helm chart requires a default dynamic provisioning which local hostpath is not the case. So a separate stable/nfs-server-provisioner was deployed using the hekm chart. The k3s has inbuilt hemchart resource that came in handy for easy helmchart deployment. For simplycisty the nfs-server-provisoner was left with default settings that uses emptyDir for the mount volume.
```
apiVersion: k3s.cattle.io/v1
kind: HelmChart
metadata:
  name: nfs
  namespace: kube-system
spec:
  chart: stable/nfs-server-provisioner
  targetNamespace: nfs-provisioner
  valuesContent: |-
    storageClass:
      defaultClass: true
```

install_consul finally deploys the stable/consul helmchart. For this demo a single node consul is used due to resource constraints. This is a very simple setup of consul. In production, consul is deployed with multiple nodes, preferrably master nodes with multiple replicas and multiple agents as daemonsets running on each kubernetes worker nodes. In that case you will need to provide appropriate helm values to create anti affinity rules so the consul nodes run on muliple kubernetes nodes.
```
apiVersion: k3s.cattle.io/v1
kind: HelmChart
metadata:
  name: consul
  namespace: kube-system
spec:
  chart: stable/consul
  targetNamespace: consul-cluster
  valuesContent: |-
    Replicas: 1
```
The delivery output for this prototype is to be able to access the consul UI externally. Note that the values.yml for the helm deploy are passed as a valueContent in this HelmChart yaml. However, I was not able to get ingress work with passing the ingress.enabled settings above. So a separate ingress resource was deployed that expose the consul UI service in port 80 and 443.
```
apiVersion: extensions/v1beta1
kind: Ingress
metadata:
  name: ui
spec:
  rules:
  - host:
    http:
      paths:
      - path: /
        backend:
          serviceName: consul-ui
servicePort: 8500
```

## Considerations for Production deployment:
This is just a POC deployment and not suitable for any production deployment. First the k3s used here is "lightweight kuberenets", and on top of that this was deployed on a single k3s node as a master and agent running on a single ec2 micro instance. Several considerations are to be taken here to be securely and reliably deploy into production:
- Use a separate kubernetes cluster (openshift or full kubernetes installation , or in cloud like AWS EKS, Google GKE etc). The fully fetaured cluster build that way will have robust security built in.
- Use an external storage for statefulset pods. Currently in this demo, a nfs-server-provisioner was used with local storage. For the pods (consul nodes) to be reliable there need to be multiple k8s worker nodes, multiple master and etcd. You can use nfs-server-provisioner or other external storage like glusterfs.
- Limit the resource usage of pods to maintain the health of kubernetes worker nodes.
Have a CA signed certificate for the cluster than the one used default in this demo.
- Start with implicit deny as a default network policy in the namespace. Allow to communicate only on the specific ports
- Use TLS connection in ingress with CA signed certificate so the API access to the consul are secure. Currently it uses the k3s cluster certificate example.com which fails verification on the client
- Configure the consul cluster with anti-affinity rules so they are placed in separate nodes.
- Use kubernetes readiness probe to monitor the consul by using the http API Probe.
- Use the TLS connection and CA signed certificate for HTTP API call to the consul, and limit the access with acl tokens.
- Collect the consul health metrics, along with the k3s cluster health and use the tools like Prometheus and Datadog, and use the visualization tools like grafana to monitor and analyse these metrics. Based on these metrics horizontal auto scaling of pods can be configured.



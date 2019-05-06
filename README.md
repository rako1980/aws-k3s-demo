# Prototype Consul running in k3s
Consul is a tool for service discovery, configuration and orchestration. This project uses AWS resources to create AWS infrastructure using tarraform, and invoke ansible-playbook to install k3s single master/single node. A helm nfs-server-provisioner is deployed to provide a default storage class, the storage to be later claimed by consule pod(s).

### Prerequisites:
It is assumed you have an access to your AWS console. So get ready your ACCESS_CODE and SECRET_KEY. The deployment script will import your public key to AWS key-pair. So get or generate your public key ready. Terraform and ansible installation is required.
``` 
$ssh=keygen -t rsa -b 2048 
(accept the default)
$wget https://releases.hashicorp.com/terraform/0.11.13/terraform_0.11.13_linux_amd64.zip 
$unzip terraform_0.11.13_linux_amd64.zip
$cp terraform /usr/local/bin/.
$yum install ansible
```

### Installation Steps:
Clone this repo, chnage the variable.yml default values as needed, or you can also export the environment variable as below. You will need to install the terraform and ansible for this to work. After initilizing terraform in the directory, when you apply the terraform the output will be displayed at last with your consul url to access.
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
Consul UI url can be accessed at http or https://[instance public ip address]/ui


## Deployment explanation:
### variable.tf
Defimes all the aws infsratcure variables. By default it uses free tier rhel7 linux AMI and t2.micro instance.
### main.cf
All major terraform resources are defined in this file. 
aws_key_pair: This will create an aws key pair with your public key contents. 
It will also deploy a new VPC with cidr block 10.0.0.0/16 rather than using the AWS default VPC. A new subnet, inetrnet gateway, routing table is created for this VPC. An elastic IP addrress is reserved to be assigned to EC2 isntance. An EC2 instance is created with public IP accessebile from internet. A security group that allows port 22 (for ssh to the EC2 instance incase you would need to login to troubelshoot, and HTTP/S port 80 and 443 to access the consul UI.

After the EC2 instance is initialized, a local provisioner populates the inventory file at ./inventory/hosts, and invokes remote exec to patch the OS and install prerq of python so that the OS can be configured with ansible. Note the inventory hosts group_vars (./inventory/group_vars/all) that defines the user and ssh private key file to ssh into the server. Ansible uses ssh for a remote execution of the playbook. Finally an ansible playbook provision.yml is invoked that will setup k3s and deploy helmc chart for the consul.

### Ansible provision.yml and roles/
> roles/
> - setup_k3s
> - install_consul
 
setup_k3s role installs k3s from the source script located at https://get.k3s.io in a single master/ single node configuration. An nfs provisioner helm chart is deployed to be used as a default dynamic provisioner. Note that k3s also provides thee local-path-provisioner yaml config to configure the local storage using host path. However, the consul helm chart requires a default dynamic privisioning which local hostpath is the case. So a separate stable/nfs-server-provisioner was deployed using the hekm chart. The k3s has inbuilt hemchart resource that came in handy for easy helmchart deployment.
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

install_consul finally deploys the stable/consul helmchart. For this demo a single node consul is used due to rsource contraints. This is a very simple setup of consul. In production, consule is deployed with multiple nodes, preferrably a master and multiple agents. In that case you will need to provide appropriate helm values to create anti affinmity rules so the consul nodes run on muliple kubernetes nodes.
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
The delivery output for this prototype is to be able to access the consul UI externally. Note that the values.yml for the heml deploy are passed as a valueContent in this HelmChart yaml. However, I was not able to get ingress work with passing the ingress.enabled settings above. So a separate ingress was deployed that expose the consule UO service in port 80 and 443.
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
 

#!/bin/bash
set -e

#Run previous chapters

 ./scripts-by-chapter/chapter-1.sh
 ./scripts-by-chapter/chapter-2.sh

 echo "***************************************************"
 echo "********* CHAPTER 3 - STARTED AT $(date) **********"
 echo "***************************************************"
 echo "--- This could take around 10 minutes"

 # Create OIDC Provider and connect it with EKS
 eksctl utils associate-iam-oidc-provider --cluster=eks-acg --approve

 # Create IAM Policies of Bookstore Microservices
 ( cd clients-api/infra/cloudformation && ./create-iam-policy.sh ) & \
 ( cd resource-api/infra/cloudformation && ./create-iam-policy.sh ) & \
 ( cd inventory-api/infra/cloudformation && ./create-iam-policy.sh ) & \
 ( cd renting-api/infra/cloudformation && ./create-iam-policy.sh ) &
 wait

 # Getting NodeGroup IAM Role from Kubernetes Cluster
 nodegroup_iam_role=$(aws cloudformation list-exports --query "Exports[?contains(Name, 'nodegroup-eks-node-group::InstanceRoleARN')].Value" --output text | xargs | cut -d "/" -f 2)

 # Removing DynamoDB Permissions from the node
 aws iam detach-role-policy --role-name ${nodegroup_iam_role} --policy-arn arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess

 # Create IAM Service Accounts (sequential execution)
 resource_iam_policy=$(aws cloudformation describe-stacks --stack development-iam-policy-resource-api --query "Stacks[0].Outputs[0]" | jq -r .OutputValue)
 renting_iam_policy=$(aws cloudformation describe-stacks --stack development-iam-policy-renting-api --query "Stacks[0].Outputs[0]" | jq -r .OutputValue)
 inventory_iam_policy=$(aws cloudformation describe-stacks --stack development-iam-policy-inventory-api --query "Stacks[0].Outputs[0]" | jq -r .OutputValue)
 clients_iam_policy=$(aws cloudformation describe-stacks --stack development-iam-policy-clients-api --query "Stacks[0].Outputs[0]" | jq -r .OutputValue)

 eksctl create iamserviceaccount --name resources-api-iam-service-account \
     --namespace development \
         --cluster eks-acg \
             --attach-policy-arn ${resource_iam_policy} --approve

             eksctl create iamserviceaccount --name renting-api-iam-service-account \
                 --namespace development \
                     --cluster eks-acg \
                         --attach-policy-arn ${renting_iam_policy} --approve

                         eksctl create iamserviceaccount --name inventory-api-iam-service-account \
                             --namespace development \
                                 --cluster eks-acg \
                                     --attach-policy-arn ${inventory_iam_policy} --approve

                                     eksctl create iamserviceaccount --name clients-api-iam-service-account \
                                         --namespace development \
                                             --cluster eks-acg \
                                                 --attach-policy-arn ${clients_iam_policy} --approve

                                                 # Upgrading the applications
                                                 ( cd ./resource-api/infra/helm-v2 && ./create.sh ) & \
                                                 ( cd ./clients-api/infra/helm-v2 && ./create.sh ) & \
                                                 ( cd ./inventory-api/infra/helm-v2 && ./create.sh ) & \
                                                 ( cd ./renting-api/infra/helm-v2 && ./create.sh ) &
                                                 wait

                                                 # Updating IRSA for AWS Load Balancer Controller
                                                 helm del -n kube-system aws-load-balancer-controller  # Uninstall first
                                                 aws_load_balancer_iam_policy=$(aws cloudformation describe-stacks --stack aws-load-balancer-iam-policy --query "Stacks[0].Outputs[0]" | jq -r .OutputValue)
                                                 aws iam detach-role-policy --role-name ${nodegroup_iam_role} --policy-arn ${aws_load_balancer_iam_policy}
                                                 ( cd ./Infrastructure/k8s-tooling/load-balancer-controller && ./create-irsa.sh )

                                                 # Updating IRSA for External DNS
                                                 helm del external-dns  # Uninstall first
                                                 external_dns_iam_policy="arn:aws:iam::aws:policy/AmazonRoute53FullAccess"
                                                 aws iam detach-role-policy --role-name ${nodegroup_iam_role} --policy-arn ${external_dns_iam_policy}
						 
						# Wait for AWS Load Balancer webhook service endpoints to become available
						  echo "Waiting for AWS Load Balancer webhook service endpoints..."
						  until kubectl get endpoints aws-load-balancer-webhook-service -n kube-system -o jsonpath='{.subsets[0].addresses[0].ip}' 2>/dev/null | grep -q '.'; do  
						  echo "Waiting for webhook endpoints..."
						      sleep 5
						      done
 						      echo "Webhook service endpoints are now available."
                                                 ( cd ./Infrastructure/k8s-tooling/external-dns && ./create-irsa.sh )

                                                 # Updating IRSA for VPC CNI
                                                 vpc_cni_iam_policy="arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
						 
						 # Check if the policy is attached to the role
						  attached=$(aws iam list-attached-role-policies --role-name "${nodegroup_iam_role}" \
						      --query "AttachedPolicies[?PolicyArn=='${vpc_cni_iam_policy}']" --output text)
						 
						      if [ -n "$attached" ]; then
						 
						 echo "Detaching VPC CNI policy..."
						aws iam detach-role-policy --role-name "${nodegroup_iam_role}" --policy-arn "${vpc_cni_iam_policy}"	 
					 	else
						    echo "Policy ${vpc_cni_iam_policy} is not attached to role ${nodegroup_iam_role}. Skipping detach." 
						fi

						 ( cd ./Infrastructure/k8s-tooling/cni && ./setup-irsa.sh )

                                                 echo "*************************************************************"
                                                 echo "********* READY FOR CHAPTER 4 - FINISHED AT $(date) *********"
                                                 echo "*************************************************************"

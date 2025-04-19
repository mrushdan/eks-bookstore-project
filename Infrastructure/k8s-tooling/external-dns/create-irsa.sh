#!/bin/bash
set -e

 Get the directory of this script so paths work regardless of the current directory
 SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

 # Define a list of valid AWS regions (update as needed)
 VALID_REGIONS=(
   "ap-south-1" "eu-north-1" "eu-west-3" "eu-west-2" "eu-west-1"
     "ap-northeast-3" "ap-northeast-2" "ap-northeast-1"
       "ca-central-1" "sa-east-1"
         "ap-southeast-1" "ap-southeast-2"
           "eu-central-1"
             "us-east-1" "us-east-2" "us-west-1" "us-west-2"
             )

             # Function to check if a region is valid
             is_valid_region() {
               local input_region=$1
                 for region in "${VALID_REGIONS[@]}"; do
                     if [ "$input_region" == "$region" ]; then
                           return 0
                               fi
                                 done
                                   return 1
                                   }

                                   # If AWS_REGION is set, use it. Otherwise, prompt the user.
                                   if [ -n "$AWS_REGION" ]; then
                                     echo "AWS_REGION is already set to '$AWS_REGION'. Using it."
                                       REGION="$AWS_REGION"
                                       else
                                         read -p "AWS_REGION is not set. Please enter your AWS region (e.g., us-east-1): " REGION
                                         fi

                                         # Validate the region; if invalid, keep prompting.
                                         while ! is_valid_region "$REGION"; do
                                           echo "Error: '$REGION' is not a valid AWS region."
                                             read -p "Please enter a valid AWS region (e.g., us-east-1): " REGION
                                             done

                                             echo "Using AWS region: $REGION"

                                             # Write/update the override file in the same directory as this script
                                             OVERRIDE_FILE="$SCRIPT_DIR/.external-dns.override.yaml"
                                             cat <<EOF > "$OVERRIDE_FILE"
                                             provider: aws
                                             env:
                                               - name: AWS_REGION
                                                   value: "$REGION"
                                                   EOF

                                                   echo "Updated override file ($OVERRIDE_FILE):"
                                                   cat "$OVERRIDE_FILE"

                                                   # Add the external-dns Helm repository (if not already added)
                                                   helm repo add external-dns https://kubernetes-sigs.github.io/external-dns/ || true
                                                   helm repo update
                                                   # Create the IAM Service Account for external-dns
                                                   service_account_name="external-dns-service-account"

                                                   eksctl create iamserviceaccount --name ${service_account_name} \
                                                       --cluster eks-acg \
                                                           --attach-policy-arn arn:aws:iam::aws:policy/AmazonRoute53FullAccess --approve

                                                           # Upgrade or install external-dns with the service account settings and region override file
                                                           helm upgrade --install external-dns external-dns/external-dns \
                                                             --set serviceAccount.create=false \
                                                               --set serviceAccount.name=${service_account_name} \
                                                                 -f "$SCRIPT_DIR/values.yaml" \
                                                                   -f "$OVERRIDE_FILE"

                                                                   echo "Helm upgrade/install completed."

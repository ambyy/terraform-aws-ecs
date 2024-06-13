Instructions to run and test:

Prerequisites :
     - Terraform
     - AWS account

1. Clone the repo mentioned above and change directory to the cloned repo.

2. Open the 'terraform.tfvars' file and provide the relevant values against each variable and save the file. You can retrieve these credentials from your AWS login. Note that this approach is taken so that the script is self-contained, with all the required data as part of the script. This approach is very specific to this solution and not general practice. 

3. With your current working directory set to the directory where the repo was cloned, run the following commands on your command line to deploy the infrastructure:

	    - terraform init
	    - terraform apply -auto-approve

3. After the second command above is complete, you will see the DNS of the load balancer on the terminal against a variable called "app_url"

4. Copy and paste the value of "app_url" in a browser window and you should see a hello world page.

5. Run the following command to destroy the infrastructure: terraform destroy -auto-approve

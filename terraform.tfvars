##################################################################################
# TF VARS
##################################################################################

aws_access_key = "xxxxxxxxxxxxxxxxxxxx"

aws_secret_key = "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"

bucket_name = "xxxxxxxxx"

key_name = "vockey"

region = "us-east-1"

private_key_path = "./key/private.key.pem" 

prefix_tag = {
    Development = "NPA21-Dev"
    Production = "NPA21-Prod"
}

network_address_space = {
    Development = "10.100.0.0/16"
    Production = "10.0.0.0/16"
}

subnet_count = {
    Development = 2
    Production = 4
}

instance_count = {
    Development = 2
    Production = 4
    Max = 6
    Min = 1
}

instance_size = {
    Development = "t2.micro"
    Production = "t2.medium"
}


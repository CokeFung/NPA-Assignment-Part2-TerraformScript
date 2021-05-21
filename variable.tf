##################################################################################
# VARIABLES
##################################################################################

variable "aws_access_key" {}
variable "aws_secret_key" {}
variable "private_key_path" {}
variable "key_name" {}
variable "region" {}
variable "bucket_name" {}

variable "prefix_tag" {
    type = map(string)
}
variable "network_address_space" {
    type = map(string)
}
variable "subnet_count" {
    type = map(number)
}
variable "instance_count" {
    type = map(number)
}
variable "instance_size" {
    type = map(string)
}

##################################################################################
# LOCAL VARS
############################################################################

locals {
    env_name = var.prefix_tag[terraform.workspace]
}
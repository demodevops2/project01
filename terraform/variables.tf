#variable "access_key" {}
#variable "secret_key" {}
variable "region" {}

variable "allowed_cidr_blocks" {
   type = list
   default = ["0.0.0.0/0","0.0.0.0/0"]
   }
variable "ami" {}
variable "instance_type" {}
#variable "keyname" {}


variable "lb_logs_s3bucket" {
  type    = string
  default = "basicapp-lb-logs2"
}

variable "basic_app_subnets" {
  type = list(object({
    availability_zone = string
    cidr_block        = string
    name              = string
  }))
  default = [
    {
      availability_zone = "eu-west-3a"
      cidr_block        = "10.0.0.0/24"
      name              = "basic_app3a"
    },
    {
      availability_zone = "eu-west-3b"
      cidr_block        = "10.0.1.0/24"
      name              = "basic_app3b"
    },
    {
      availability_zone = "eu-west-3c"
      cidr_block        = "10.0.2.0/24"
      name              = "basic_app3c"
    }
  ]
}

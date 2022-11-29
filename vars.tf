variable "nsgip" {
 description = "Workstation external IP to allow connections to JB, Kibana"
 default = "test"
}

variable "ssh_user" {
 default = "neha"
}

variable "admin_password" {
 description = "Default password"
}

variable "subscription_id" {
    default = "dc2b70a9-be62-43d4-85fd-c66503a43a99"
}

variable "client_id" {
    default = "5b0f8977-0cbc-4a83-bb13-43ed2394b514"
}

variable "client_secret" {
    default = "qczbYor4LNtnhcbTGX~6.PpCia657ImAbX"
}

variable "tenant_id" {
    default = "93c57c5b-48a2-4b7c-abc2-b3fb5a845b6d"
}
# Lee SOLO las salidas del componente de red del mismo entorno (solo lectura).
data "terraform_remote_state" "red" {
  backend = "s3"

  config = {
    bucket = "modalima-tfstate-111122223333"
    key    = "env/prod/red/terraform.tfstate"
    region = "us-east-1"
  }
}

locals {
  subredes_privadas = data.terraform_remote_state.red.outputs.ids_subredes_privadas
}

# 1) Renombrar sin destruir: el recurso ahora se llama "principal".
moved {
  from = aws_sqs_queue.pedidos
  to   = aws_sqs_queue.principal
}

# 2) Adoptar un bucket creado en la consola.
import {
  to = aws_s3_bucket.adoptado
  id = "modalima-catalogo-prod"
}

resource "aws_s3_bucket" "adoptado" {
  bucket = "modalima-catalogo-prod"
}

# 3) Dejar de gestionar sin borrar el recurso real.
removed {
  from = aws_s3_bucket.heredado

  lifecycle {
    destroy = false
  }
}

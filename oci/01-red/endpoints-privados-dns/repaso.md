# Oracle OCI · Red · Service Gateway, endpoints privados y DNS privado · Repaso

## Preguntas
1. ¿Qué diferencia hay entre Service Gateway y endpoint privado?
2. ¿Qué tres cosas necesita un Service Gateway para funcionar?
3. ¿Qué es una vista privada de DNS?
4. ¿Para qué sirve un endpoint de reenvío?
5. ¿Para qué un endpoint de escucha?
6. ¿Por qué probar el DNS desde el pod?
7. ¿La red privada reemplaza a IAM?
8. ¿Qué pasa si una «base privada» resuelve a una IP pública?
9. ¿Qué es un `SERVICE_CIDR_BLOCK`?
10. ¿Cuándo usar nombres internos de VCN?

## Respuestas
1. SGW: acceso general a servicios de Oracle por la red interna; endpoint privado: IP privada de un recurso concreto en tu subred.
2. El gateway, una ruta al CIDR del servicio y reglas de seguridad de salida.
3. Un conjunto de zonas privadas visible solo para las VCN asociadas.
4. Enviar consultas de ciertos dominios a un DNS externo (p. ej., on-premises).
5. Permitir que redes externas consulten tus zonas privadas.
6. Porque la resolución depende del resolutor de esa VCN, no del de tu laptop.
7. No: el principal igual necesita políticas.
8. Se está usando el nombre público; el endpoint privado no se está utilizando.
9. Un destino de ruta que representa a los servicios de Oracle.
10. Para nombrar instancias dentro de la VCN sin registros adicionales.

## Ejercicios
1. Escribe las reglas de ruta y seguridad para llegar a Object Storage desde una subred privada.
2. Crea una zona `tienda.interno` con un registro `pedidos-db`.
3. Diseña el DNS híbrido con una oficina que usa `corp.interno`.

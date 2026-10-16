# Azure · Container Apps · Repaso

## Preguntas de repaso
1. ¿Qué es un entorno y qué comparten las apps que viven en él?
   - *La frontera de red y de logs: VNet, DNS interno y workspace de Log Analytics.*
2. ¿Qué es una revisión y por qué es inmutable?
   - *Una foto de la plantilla; cada cambio crea una nueva, lo que permite reparto de tráfico y reversión rápida.*
3. ¿Diferencia entre modo de revisión *single* y *multiple*?
   - *Single: solo la última está activa. Multiple: varias a la vez y tú repartes el tráfico (azul/verde).*
4. ¿Cómo se escala a cero y qué cuesta?
   - *`minReplicas = 0`; el primer request espera el arranque en frío.*
5. ¿Qué regla usas para un worker de colas y cómo se autentica?
   - *Regla KEDA `azure-servicebus`, autenticada por identidad administrada con rol *Service Bus Data Receiver*.*
6. ¿Cómo llama una app a otra del mismo entorno?
   - *Por su nombre (`http://api-pedidos`) o su FQDN interno; no por `localhost`.*
7. ¿Qué aporta Dapr y cuándo no lo usarías?
   - *APIs estándar de invocación, pub/sub, estado y secretos; no lo uses si añade complejidad sin resolver un problema real.*
8. ¿Cuándo un Job es mejor que un Container App?
   - *Cuando el trabajo termina: reportes, migraciones, procesamiento por evento.*
9. ¿Cómo se descarga la imagen de ACR sin contraseña?
   - *Identidad administrada con `AcrPull` configurada como identidad del registro.*
10. ¿Por qué rotar un secreto de Key Vault requiere reiniciar la revisión?
    - *Las variables de entorno se leen al arrancar la réplica.*
11. ¿Cómo consigues una IP de salida fija?
    - *Entorno de workload profiles en VNet con NAT Gateway.*
12. ¿Cuándo eliges AKS en lugar de Container Apps?
    - *Cuando necesitas la API de Kubernetes, operadores, mallas completas, DaemonSets o control de nodos.*

## Entrevista
- Diseña la migración de 6 APIs de App Service a Container Apps ahorrando costo nocturno sin afectar al usuario.
- Describe un despliegue azul/verde con reversión inmediata.
- ¿Cómo evitas que un worker escalado a 25 réplicas tumbe tu base de datos?
- ¿Qué medirías para decidir `minReplicas` de una API Spring Boot?
- ¿Cómo haces que un servicio sea accesible solo desde la red privada?

## Ejercicio práctico
1. Crea un entorno y despliega una API con `containerapp.yaml` (sondas incluidas).
2. Pasa a modo *multiple*, despliega `v2`, reparte 10 % y vuelve atrás.
3. Crea un worker con regla de Service Bus y observa 0 → N réplicas enviando mensajes.
4. Programa un Job y fuerza un fallo (código ≠ 0) para ver el reintento.

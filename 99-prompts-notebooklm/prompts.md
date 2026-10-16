# Prompts para NotebookLM (Video Overview)

## Cómo usarlo

1. Crea **un notebook por módulo**. Para videos más profundos, un notebook por servicio (por ejemplo, solo VNet, solo AKS).
2. Sube como fuentes los `.md` del módulo, más `PLANTILLA-SERVICIO.md`.
3. En Video Overview, abre "Personalizar" y pega el **prompt maestro** y luego el **añadido del módulo**.
4. Si el cuadro limita caracteres, usa la **versión corta**.

Notas:
- No puedes fijar una duración exacta. Cuanto más acotadas las fuentes, más detalle por servicio.
- Las funciones de NotebookLM cambian; si algo no aparece, revisa el menú actual.
- Genera también el **Audio Overview** del mismo notebook para repasar caminando.

---

## Prompt maestro

```
Crea un video explicativo en español latinoamericano, tono didáctico y cercano, para una persona que aprende cloud desde cero hasta nivel intermedio y trabaja como ingeniero de software con Java.

Para CADA servicio de las fuentes sigue siempre este orden:
1. Qué es, con una analogía de la vida real.
2. Para qué sirve y cuándo NO usarlo.
3. Un caso de uso real contado como historia (problema, solución, resultado, lección).
4. Cómo se usa, paso a paso: portal, CLI y Terraform.
5. Qué se debe hacer y qué NO se debe hacer, con errores típicos.
6. Equivalente en AWS, Oracle OCI y Google Cloud, y en qué se diferencian de verdad.
7. Cómo se manejan IAM, políticas y acceso por red privada en ese servicio.
8. Qué revisar cuando no funciona.

Reglas:
- No omitas ningún servicio, concepto ni tabla de las fuentes.
- Define cada término técnico la primera vez que aparezca.
- Usa diagramas y comparaciones visuales cuando ayuden.
- Cierra cada servicio con un resumen de 3 puntos y 2 preguntas de repaso.
- Prioriza ejemplos concretos sobre teoría abstracta.
- No inventes datos que no estén en las fuentes; si algo depende de la versión, dilo.
```

## Versión corta

```
Video en español latinoamericano, didáctico, para aprender cloud de cero a intermedio. Por cada servicio: analogía, para qué sirve y cuándo no, caso real, uso paso a paso, qué hacer y qué no, equivalente en Azure, AWS, OCI y GCP, IAM y red privada, y qué revisar si falla. No omitas nada de las fuentes. Cierra cada servicio con 3 puntos de resumen y 2 preguntas.
```

---

## Añadidos por módulo

### 00 · Fundamentos
```
Enfócate en: IaaS vs PaaS vs FaaS vs SaaS con la analogía de la pizza, la jerarquía de recursos en las 4 nubes (tenant/suscripción/grupo, organización/cuenta, tenancy/compartimento, organización/carpeta/proyecto), el modelo de responsabilidad compartida y el caso ModaLima. Muestra la tabla de equivalencias de nombres y el glosario.
```

### 01 · Networking
```
Enfócate en: cómo calcular CIDR y cuántas IP quedan por subnet en cada nube, cómo se evalúan las reglas de NSG por prioridad, por qué dentro de una VNet todo se habla por defecto, peering no transitivo, hub-spoke, Private Endpoint vs Service Endpoint, y por qué el DNS privado es lo que más falla. Compara con VPC, VCN y VPC de GCP (que es global).
```

### 02 · Comunicación privada y diagnóstico
```
Cuenta este módulo como historias de detectives. Explica la regla RPDSI (Ruta, Permiso, DNS, Servicio, Identidad) y la escalera de diagnóstico. Distingue claramente: error de DNS, timeout, connection refused, error TLS, 401/403 y 5xx, y qué significa cada uno. Recorre los escenarios de AKS (nodos NotReady, ImagePullBackOff, LoadBalancer en Pending, kubectl que no conecta) y de APIM (500, 502, 504 hacia un backend privado). Repite los checklists para EKS, OKE y GKE, y para API Gateway de cada nube.
```

---

### 03 · IAM y seguridad
```
Enfócate en: diferencia entre autenticación y autorización; Entra ID vs Azure RBAC; plano de control vs plano de datos; roles vs políticas; mínimo privilegio; Managed Identity y Workload Identity; cómo se escribe EL MISMO permiso en Azure RBAC, AWS IAM (política, trust policy, SCP), OCI (policy statements y dynamic groups) y GCP IAM (bindings y service accounts); federación OIDC para CI/CD sin secretos. Cierra con errores 403 típicos y cómo diagnosticarlos.
```

### 04 · Secretos y claves
```
Enfócate en: diferencia entre secretos, claves y certificados; Key Vault con RBAC; soft delete y purge protection; cómo una app Java lee un secreto SIN contraseñas (identidad administrada); CSI Secret Store en AKS; rotación; claves gestionadas por el cliente (CMK); acceso por Private Endpoint. Compara con Secrets Manager + KMS, OCI Vault y Secret Manager + Cloud KMS.
```

### 05 · Compute
```
Enfócate en: el árbol de decisión (App Service, Functions, Container Apps, AKS, VMs); escalado y costos de cada opción; ejemplo de Function en Java y de Deployment/Service/HPA en AKS; por qué no todo debe ir a Kubernetes. Equivalentes: Elastic Beanstalk/App Runner/Lambda/EKS, OCI Functions/OKE/Container Instances, Cloud Run/Cloud Functions/GKE.
```

### 06 · Ingress y API
```
Enfócate en el viaje completo de una petición: Internet → Front Door/WAF → Application Gateway → APIM → AKS (Ingress/Gateway API) → backend. Explica qué hace cada capa, políticas de APIM en XML (validar JWT, límite de llamadas, reescritura, caché), versionado, health probes y errores 502/504. Compara con CloudFront/ALB/API Gateway, OCI LB/API Gateway y Cloud Armor/Cloud Load Balancing/API Gateway. Aclara qué cambió con el retiro anunciado de ingress-nginx y la Gateway API.
```

### 07 · Storage (SAS / Presigned / PAR / Signed URL / Claim Check)
```
Dedica la MAYOR parte del video al acceso temporal: SAS de Azure (usuario delegado, de servicio y de cuenta), Presigned URL de AWS, Pre-Authenticated Request de OCI y Signed URL de GCP. Para cada una explica: cómo se genera, permisos de LECTURA y de ESCRITURA, expiración, qué se firma, cómo se revoca, y los errores graves (SAS de cuenta de larga duración, en logs o en repositorios). Explica el patrón Claim Check: guardar el archivo en el storage y enviar por una cola SOLO la referencia; cuándo generar la URL de lectura (al procesar, no al encolar). Incluye los eventos al subir un archivo (Event Grid, S3 Events, OCI Events, GCS a Pub/Sub) y el acceso por red privada.
```

### 08 · Mensajería y streaming
```
Enfócate en: cola vs tópico vs stream con una analogía cotidiana; equivalente de Kafka en cada nube (Event Hubs con endpoint Kafka, MSK, OCI Streaming, Managed Kafka/Pub/Sub); particiones, clave de partición y orden; consumer groups; retención y replay; entrega al menos una vez e idempotencia; DLQ; patrón outbox. Incluye cuándo elegir cola y cuándo stream, y los errores de red e IAM más comunes (puerto 9093, SASL, roles).
```

### 09 · Bases de datos
```
Enfócate en: relacional vs NoSQL; Azure SQL, PostgreSQL Flexible Server y Cosmos DB (RU/s, partition key, niveles de consistencia); alta disponibilidad vs backup vs recuperación ante desastres; pool de conexiones y la regla para no agotarlo; acceso privado e identidad administrada. Compara con RDS/Aurora/DynamoDB, Autonomous DB/MySQL HeatWave/NoSQL de OCI, y Cloud SQL/AlloyDB/Firestore/Spanner.
```

### 10 · Políticas y gobierno
```
Enfócate en: diferencia entre IAM ("quién puede") y políticas ("qué está permitido"); efectos Deny, Audit, Modify, DeployIfNotExists; herencia por jerarquía; ejemplos reales: bloquear IP pública, exigir etiquetas, limitar regiones. Equivalentes: SCP y Config, Security Zones y Cloud Guard, Organization Policy. Incluye locks, landing zones y control de costos con presupuestos.
```

### 11 · Terraform (IaC)
```
Explica Terraform como "plano + inspector" para las 4 nubes. Cubre: providers, resources, data sources, variables, outputs, state (por qué es sensible), backends remotos con bloqueo en Azure, AWS, OCI y GCP, módulos, plan/apply/destroy, drift, import y moved, lifecycle, pipelines con OIDC, tflint/Checkov y OpenTofu. Recorre el MISMO laboratorio (red privada + storage sin acceso público) en las 4 nubes, resaltando qué recurso equivale a cuál. Menciona alternativas nativas (Bicep, CloudFormation, Resource Manager, Infrastructure Manager).
```

### 12 · Casos integrados
```
Cuenta los casos A–D como arquitecturas de punta a punta, siguiendo una petición paso a paso: tienda online, subida de archivos con Claim Check, clickstream con Kafka y landing zone. Para cada uno, muestra la arquitectura en Azure y su equivalente en AWS, OCI y GCP. Recorre el runbook de incidente (DNS → ruta → puerto → TLS → servicio → identidad → aplicación) y el checklist de producción. Cierra con el plan de estudio de 8 semanas.
```

---

## Prompt para generar quiz de estudio

```
Con las fuentes, crea 20 preguntas de opción múltiple de nivel intermedio, mezclando conceptos, casos de la vida real y troubleshooting. Incluye equivalencias entre Azure, AWS, OCI y GCP. Después de cada respuesta, explica por qué las otras opciones son incorrectas.
```

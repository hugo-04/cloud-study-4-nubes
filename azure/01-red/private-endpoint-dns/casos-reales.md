# Azure · Private Endpoint y DNS · Casos reales

## Caso 1 · El Private Endpoint que nadie usaba
- **Problema:** ModaLima creó un PE para su base de datos y cerró el acceso público. La aplicación dejó de conectar.
- **Pistas:** `nslookup` desde el pod devolvía una **IP pública**.
- **Causa:** la zona `privatelink.database.windows.net` no estaba enlazada a la VNet de AKS.
- **Solución:** crear el *virtual network link*.
- **Lección:** PE sin DNS = no funciona. DNS es lo primero que se revisa.

## Caso 2 · Funciona desde la VM, no desde la oficina
- **Problema:** un desarrollador conectado por VPN no podía resolver el nombre de la base de datos privada.
- **Causa:** el DNS de la oficina no sabía de las zonas `privatelink`.
- **Solución:** DNS Private Resolver con endpoint de entrada y reenvío condicional desde el DNS de la oficina.
- **Lección:** on-premises necesita su propio camino de resolución hacia Azure.

## Caso 3 · Dos zonas, dos respuestas
- **Problema:** una API resolvía bien el storage en `prod` y mal en `dev`.
- **Causa:** `dev` tenía su propia copia de la zona privada, sin el registro del PE.
- **Solución:** zona única en el hub, enlazada a todas las VNets.
- **Lección:** centraliza las zonas privadas.

## Caso 4 · Conexión `Pending` eterna
- **Problema:** un PE hacia un servicio de otro equipo quedó en `Pending`.
- **Causa:** el recurso pertenecía a otra suscripción y nadie aprobó.
- **Solución:** aprobar la conexión desde el recurso destino.
- **Lección:** PE entre suscripciones requiere aprobación manual.

## Caso 5 · Error de certificado al usar la IP
- **Problema:** para "saltarse el DNS", un desarrollador conectó a `10.10.9.4` y recibió error TLS.
- **Causa:** el certificado es válido para el nombre del servicio, no para la IP.
- **Solución:** arreglar el DNS y conectar siempre por nombre.
- **Lección:** nunca por IP.

## Caso 6 · La factura de los endpoints
- **Problema:** subió la factura de red sin tráfico nuevo.
- **Causa:** decenas de PE de pruebas olvidados.
- **Solución:** inventario con etiquetas `owner`/`env` y política que alerta PE sin etiquetas.
- **Lección:** los PE cuestan por hora, aunque no tengan tráfico.

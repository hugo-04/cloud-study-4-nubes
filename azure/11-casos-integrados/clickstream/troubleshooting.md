# Azure · Caso integrado · Clickstream · Troubleshooting

Orden: **¿el colector acepta? → ¿Event Hubs limita (429)? → ¿las particiones están parejas? → ¿el grupo del agregador avanza? → ¿Capture escribe?** Consultas en [`kql-clickstream.md`](ejemplos/kql/kql-clickstream.md).

| Síntoma | Causa probable | Cómo comprobarlo | Solución |
|---|---|---|---|
| El colector devuelve 429/503 | El namespace limita (unidades agotadas) | Métrica `ThrottledRequests` | Subir unidades o el tope de auto-inflate; reintentos con espera |
| Una partición atrasada y las demás vacías | Clave caliente | Mensajes por partición; `DetectorDeSesgo` | Cambiar la clave (sesión/cubeta); limitar al emisor abusivo |
| `ServiceBusy` / `QuotaExceeded` al publicar | Eventos sueltos y picos | Tamaño y frecuencia de los envíos | Enviar en lotes |
| Un evento «no cabe en el lote» | Evento mayor que el límite | Tamaño | Claim Check: guarda el contenido en Blob |
| El agregador no avanza | Sin permisos o sin acceso a los puntos de control | Logs del procesador; roles | *Data Receiver* y datos de blob; revisar DNS/Private Endpoint |
| Particiones sin dueño o saltando de instancia | Más instancias que particiones o puntos de control inaccesibles | Propiedad de particiones en el contenedor | Ajustar instancias ≤ particiones; revisar el contenedor |
| Cada lector ve una parte de los eventos | Comparten grupo | Grupo configurado | Un grupo por aplicación |
| Contadores bajos tras un despliegue | Ventana en memoria perdida | Hora del reinicio vs resúmenes | Recalcular desde el lago; UPSERT |
| Contadores el doble | Reintento sumando | Código de guardado | UPSERT por (ventana, página) |
| Muchos `TARDIO` | Dispositivos con reloj atrasado o conexión intermitente | Diferencia evento-vs-proceso | Ampliar la tolerancia o mover esos casos al lote |
| Capture no escribe | Falta el rol de la identidad del namespace o el contenedor | Estado de Capture y roles | *Storage Blob Data Contributor* a la identidad del namespace |
| Archivos vacíos en el lago | Sin tráfico en el intervalo | `skip_empty_archives` | Activarlo para evitar archivos vacíos |
| `terraform apply` quiere recrear el event hub | Cambió `partition_count` | Salida del plan | No lo cambies en caliente; crea otro y migra |
| Reproceso desde una fecha no devuelve nada | Fuera de la retención | Retención del event hub | Reprocesar desde el lago |

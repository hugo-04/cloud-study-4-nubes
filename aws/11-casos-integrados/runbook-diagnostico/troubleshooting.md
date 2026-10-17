# AWS · Caso integrado · Runbook de diagnóstico · Troubleshooting

Cuando falla **el propio runbook**:

| Síntoma | Causa probable | Qué hacer |
|---|---|---|
| La alarma no salta con errores reales | `treat_missing_data` mal elegido o métrica con otra dimensión (sufijo del ALB equivocado) | Mira el gráfico de la alarma; compara la dimensión con `aws elbv2 describe-load-balancers` |
| Llegan siete correos a la vez | Alarmas individuales con acción | Acciones solo en la alarma compuesta |
| No llega ningún correo | La suscripción no está confirmada, o la clave KMS del tópico no permite publicar a CloudWatch | Confirma el correo; revisa la política de la clave |
| La sonda siempre dice OK pero la app falla | La sonda no usa la misma red/identidad que la app | Ejecútala en el mismo pod/cuenta de servicio |
| `LookupEvents` devuelve `ThrottlingException` | Demasiadas personas consultando | Usa el informe guardado unos segundos ([Java](uso-en-java.md)) |
| «No hay cambios» pero hubo despliegue | Retraso de CloudTrail (hasta ~15 min) | Pregunta al equipo; revisa el historial de la herramienta de despliegue |
| Logs Insights no devuelve nada | Rango de tiempo o grupo equivocados; campos sin JSON | Verifica el grupo, el rango y que los logs sean JSON |
| El filtro de métrica de la sonda no cuenta | El patrón no coincide con la línea | Prueba el patrón con «Test pattern» en la consola |
| Alarma `sin-trafico` salta de madrugada | Poco tráfico real | Ajusta el periodo o usa una ventana por horario |
| El panel está vacío | Región o dimensiones equivocadas | Comprueba `region` y los identificadores |
| El postmortem nunca se hace | Sin responsable ni fecha | El comandante asigna al escriba antes de cerrar |

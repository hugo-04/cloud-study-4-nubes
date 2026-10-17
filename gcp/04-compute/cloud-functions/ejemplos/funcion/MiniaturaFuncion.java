// Función de eventos (Functions Framework). Dependencia: com.google.cloud.functions:functions-framework-api (verifica versión).
package com.modalima.funciones;

import com.google.cloud.functions.CloudEventsFunction;
import io.cloudevents.CloudEvent;
import java.nio.charset.StandardCharsets;
import java.util.logging.Logger;

public class MiniaturaFuncion implements CloudEventsFunction {

    private static final Logger LOG = Logger.getLogger(MiniaturaFuncion.class.getName());

    @Override
    public void accept(CloudEvent evento) {
        String datos = evento.getData() == null ? "" : new String(evento.getData().toBytes(), StandardCharsets.UTF_8);
        // Idempotencia: el id del evento y un nombre de salida determinista
        LOG.info(() -> "evento " + evento.getId() + " tipo " + evento.getType() + " (" + datos.length() + " bytes)");
        // ... procesar y escribir en un bucket DISTINTO al de entrada
    }
}

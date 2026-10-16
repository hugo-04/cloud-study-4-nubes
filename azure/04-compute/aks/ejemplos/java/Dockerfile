# Spring Boot 3.3+/4: imagen en capas, sin root, lista para Kubernetes.
# docker build -t acrmodalima.azurecr.io/api-pedidos:1.4.0 .
FROM maven:3.9-eclipse-temurin-21 AS build
WORKDIR /src
COPY pom.xml .
RUN mvn -B -q dependency:go-offline
COPY src ./src
RUN mvn -B -q package -DskipTests

FROM eclipse-temurin:21-jre AS extraer
WORKDIR /extraer
COPY --from=build /src/target/*.jar app.jar
# Separa dependencias, loader y aplicación para aprovechar la caché de capas
RUN java -Djarmode=tools -jar app.jar extract --layers --launcher --destination .

FROM eclipse-temurin:21-jre
RUN useradd --system --uid 10001 --no-create-home app
WORKDIR /app
COPY --from=extraer /extraer/dependencies/ ./
COPY --from=extraer /extraer/spring-boot-loader/ ./
COPY --from=extraer /extraer/snapshot-dependencies/ ./
COPY --from=extraer /extraer/application/ ./
USER 10001
EXPOSE 8080
# Las opciones de memoria/GC llegan por JAVA_TOOL_OPTIONS (ConfigMap)
ENTRYPOINT ["java", "org.springframework.boot.loader.launch.JarLauncher"]

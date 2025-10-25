FROM maven:3.8-openjdk-11 AS build
WORKDIR /app
COPY pom.xml .
COPY src ./src
RUN mvn clean package

FROM openjdk:11-jre-slim
WORKDIR /app
COPY --from=build /app/target/producer-1.0.0.jar app.jar
ENTRYPOINT ["java", "-jar", "app.jar"]
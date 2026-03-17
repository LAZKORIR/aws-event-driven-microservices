# Stage 1 — Build
FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build

WORKDIR /src

# Copy csproj first (cache restore)
COPY worker-service.csproj ./
RUN dotnet restore

# Copy rest
COPY . .

RUN dotnet publish -c Release -o /app

# Stage 2 — Runtime
FROM mcr.microsoft.com/dotnet/runtime:8.0

WORKDIR /app

COPY --from=build /app .

ENTRYPOINT ["dotnet", "worker-service.dll"]
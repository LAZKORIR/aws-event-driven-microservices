# Stage 1 — Build
FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build

WORKDIR /src

# Copy only project file first (for caching)
COPY api-service.csproj ./
RUN dotnet restore

# Copy everything else
COPY . .

RUN dotnet publish -c Release -o /app

# Stage 2 — Runtime
FROM mcr.microsoft.com/dotnet/aspnet:8.0

WORKDIR /app

COPY --from=build /app .

ENV ASPNETCORE_URLS=http://+:5030

EXPOSE 5030

ENTRYPOINT ["dotnet", "api-service.dll"]
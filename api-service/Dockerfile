# Local development only
# The production API runs on Windows EC2 as a Windows service

FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build

WORKDIR /src

COPY api-service.csproj ./
RUN dotnet restore

COPY . .
RUN dotnet publish -c Release -o /app

FROM mcr.microsoft.com/dotnet/aspnet:8.0

WORKDIR /app
COPY --from=build /app .

ENV ASPNETCORE_URLS=http://+:5030

EXPOSE 5030

ENTRYPOINT ["dotnet", "api-service.dll"]
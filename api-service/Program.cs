using Amazon.SecretsManager;
using Amazon.SecretsManager.Model;
using RabbitMQ.Client;
using RabbitMQ.Client.Exceptions;
using System.Security.Authentication;
using System.Text;
using System.Text.Json;
using api_service.Models;

var builder = WebApplication.CreateBuilder(args);

// Required for the process to integrate with Windows Service Control Manager
builder.Host.UseWindowsService();

// Hardcode the URL so it binds on port 80 regardless of environment variables
builder.WebHost.UseUrls("http://+:80");

builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen();
builder.Services.AddSingleton<AmazonSecretsManagerClient>();

var app = builder.Build();

app.UseSwagger();
app.UseSwaggerUI();

var summaries = new[]
{
    "Freezing","Bracing","Chilly","Cool","Mild",
    "Warm","Balmy","Hot","Sweltering","Scorching"
};

app.MapGet("/", () => Results.Ok("API is running"));
app.MapGet("/health", () => Results.Ok("Healthy"));

app.MapPost("/send", async (RequestMessage request, AmazonSecretsManagerClient secretsClient) =>
{
    try
    {
        var secretName = Environment.GetEnvironmentVariable("MQ_SECRET_NAME");

        if (string.IsNullOrWhiteSpace(secretName))
            return Results.Problem("MQ_SECRET_NAME is not set.", statusCode: 500);

        var secretValue = await secretsClient.GetSecretValueAsync(new GetSecretValueRequest
        {
            SecretId = secretName
        });

        if (string.IsNullOrWhiteSpace(secretValue.SecretString))
            return Results.Problem("RabbitMQ secret is empty.", statusCode: 500);

        var mqSecret = JsonSerializer.Deserialize<RabbitMqSecret>(secretValue.SecretString);

        if (mqSecret == null ||
            string.IsNullOrWhiteSpace(mqSecret.Host) ||
            string.IsNullOrWhiteSpace(mqSecret.Username) ||
            string.IsNullOrWhiteSpace(mqSecret.Password))
        {
            return Results.Problem("RabbitMQ secret is missing values.", statusCode: 500);
        }

        var mqHost = mqSecret.Host;
        if (mqHost.Contains(":"))
            mqHost = mqHost.Split(':')[0];

        var factory = new ConnectionFactory
        {
            HostName = mqHost,
            UserName = mqSecret.Username,
            Password = mqSecret.Password,
            Port = 5671,
            Ssl = new SslOption
            {
                Enabled = true,
                Version = SslProtocols.Tls12,
                ServerName = mqHost
            }
        };

        using var connection = factory.CreateConnection();
        using var channel = connection.CreateModel();

        channel.QueueDeclare(
            queue: "task-queue",
            durable: true,
            exclusive: false,
            autoDelete: false,
            arguments: null);

        var message = JsonSerializer.Serialize(request);
        var body = Encoding.UTF8.GetBytes(message);

        var properties = channel.CreateBasicProperties();
        properties.Persistent = true;

        channel.BasicPublish(
            exchange: "",
            routingKey: "task-queue",
            basicProperties: properties,
            body: body);

        return Results.Ok("Message sent to queue");
    }
    catch (BrokerUnreachableException ex)
    {
        return Results.Problem($"RabbitMQ unreachable: {ex.Message}", statusCode: 502);
    }
    catch (Exception ex)
    {
        return Results.Problem($"Unexpected error: {ex.Message}", statusCode: 500);
    }
});

app.MapGet("/weatherforecast", () =>
{
    var forecast = Enumerable.Range(1, 5).Select(index =>
        new WeatherForecast(
            DateOnly.FromDateTime(DateTime.Now.AddDays(index)),
            Random.Shared.Next(-20, 55),
            summaries[Random.Shared.Next(summaries.Length)]
        )).ToArray();

    return forecast;
})
.WithName("GetWeatherForecast");

app.Run();


public class RabbitMqSecret
{
    public string Host { get; set; } = string.Empty;
    public string Username { get; set; } = string.Empty;
    public string Password { get; set; } = string.Empty;
}

record WeatherForecast(DateOnly Date, int TemperatureC, string? Summary)
{
    public int TemperatureF => 32 + (int)(TemperatureC / 0.5556);
}
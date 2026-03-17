using RabbitMQ.Client;
using System.Text;
using System.Text.Json;
using api_service.Models;

var builder = WebApplication.CreateBuilder(args);

// Add services
builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen();

var app = builder.Build();

if (app.Environment.IsDevelopment())
{
    app.UseSwagger();
    app.UseSwaggerUI();
}

app.UseHttpsRedirection();

var summaries = new[]
{
    "Freezing","Bracing","Chilly","Cool","Mild",
    "Warm","Balmy","Hot","Sweltering","Scorching"
};

app.MapPost("/send", (RequestMessage request) =>
{
    var factory = new ConnectionFactory()
{
    HostName = Environment.GetEnvironmentVariable("RABBITMQ_HOST") ?? "rabbitmq"
};

    using var connection = factory.CreateConnection();
    using var channel = connection.CreateModel();

    channel.QueueDeclare(
        queue: "task-queue",
        durable: false,
        exclusive: false,
        autoDelete: false);

    var message = JsonSerializer.Serialize(request);
    var body = Encoding.UTF8.GetBytes(message);

    channel.BasicPublish(
        exchange: "",
        routingKey: "task-queue",
        basicProperties: null,
        body: body);

    return Results.Ok("Message sent to queue");
});

app.MapGet("/weatherforecast", () =>
{
    var forecast = Enumerable.Range(1,5).Select(index =>
        new WeatherForecast(
            DateOnly.FromDateTime(DateTime.Now.AddDays(index)),
            Random.Shared.Next(-20,55),
            summaries[Random.Shared.Next(summaries.Length)]
        )).ToArray();

    return forecast;
})
.WithName("GetWeatherForecast");

app.Run();

record WeatherForecast(DateOnly Date, int TemperatureC, string? Summary)
{
    public int TemperatureF => 32 + (int)(TemperatureC / 0.5556);
}
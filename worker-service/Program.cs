using RabbitMQ.Client;
using RabbitMQ.Client.Events;
using System.Text;
using System.Security.Authentication;
using Npgsql;
using System.Text.Json;

// Read connection details from environment variables injected by ECS Secrets Manager
var rabbitHost = Environment.GetEnvironmentVariable("RABBITMQ_HOST") ?? "rabbitmq";
var rabbitUser = Environment.GetEnvironmentVariable("RABBITMQ_USER") ?? "guest";
var rabbitPass = Environment.GetEnvironmentVariable("RABBITMQ_PASS") ?? "guest";
var rabbitTls  = Environment.GetEnvironmentVariable("RABBITMQ_TLS")  == "1";

// Strip port from host if present (Secrets Manager stores the full endpoint)
if (rabbitHost.Contains(":"))
    rabbitHost = rabbitHost.Split(':')[0];

var factory = new ConnectionFactory
{
    HostName = rabbitHost,
    UserName = rabbitUser,
    Password = rabbitPass,
    Port     = rabbitTls ? 5671 : 5672,
};

if (rabbitTls)
{
    factory.Ssl = new SslOption
    {
        Enabled    = true,
        Version    = SslProtocols.Tls12,
        ServerName = rabbitHost
    };
}

IConnection? connection = null;

while (connection == null)
{
    try
    {
        Console.WriteLine("Connecting to RabbitMQ...");
        connection = factory.CreateConnection();
    }
    catch (Exception ex)
    {
        Console.WriteLine($"RabbitMQ not ready ({ex.Message}), retrying in 5 seconds...");
        Thread.Sleep(5000);
    }
}

Console.WriteLine("Connected to RabbitMQ!");

using var channel = connection.CreateModel();

// Ensure the results table exists before consuming messages
EnsureTableExists();

// durable: true — must match the API service declaration
channel.QueueDeclare(
    queue:      "task-queue",
    durable:    true,
    exclusive:  false,
    autoDelete: false,
    arguments:  null);

Console.WriteLine("Waiting for messages...");

var consumer = new EventingBasicConsumer(channel);

consumer.Received += (model, ea) =>
{
    var body    = ea.Body.ToArray();
    var message = Encoding.UTF8.GetString(body);

    Console.WriteLine($"Received message: {message}");

    var data = JsonSerializer.Deserialize<RequestMessage>(
        message,
        new JsonSerializerOptions { PropertyNameCaseInsensitive = true });

    if (data != null)
    {
        SaveToDatabase(data);
        Console.WriteLine("Saved to database.");
    }
};

channel.BasicConsume(
    queue:     "task-queue",
    autoAck:   true,
    consumer:  consumer);

Console.WriteLine("Worker running...");

while (true)
    Thread.Sleep(1000);

void EnsureTableExists()
{
    var connectionString = Environment.GetEnvironmentVariable("DB_CONNECTION");
    using var conn = new NpgsqlConnection(connectionString);
    conn.Open();
    using var cmd = new NpgsqlCommand(
        @"CREATE TABLE IF NOT EXISTS results (
            id      SERIAL PRIMARY KEY,
            name    TEXT NOT NULL,
            message TEXT NOT NULL,
            created_at TIMESTAMPTZ DEFAULT NOW()
        )", conn);
    cmd.ExecuteNonQuery();
    Console.WriteLine("Database table ensured.");
}

void SaveToDatabase(RequestMessage data)
{
    var connectionString = Environment.GetEnvironmentVariable("DB_CONNECTION");
    using var conn = new NpgsqlConnection(connectionString);
    conn.Open();
    using var cmd = new NpgsqlCommand(
        "INSERT INTO results(name, message) VALUES (@name, @message)", conn);
    cmd.Parameters.AddWithValue("name",    data.Name);
    cmd.Parameters.AddWithValue("message", data.Message);
    cmd.ExecuteNonQuery();
}

public class RequestMessage
{
    public string Name    { get; set; } = string.Empty;
    public string Message { get; set; } = string.Empty;
}
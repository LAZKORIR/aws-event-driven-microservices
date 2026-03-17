using RabbitMQ.Client;
using RabbitMQ.Client.Events;
using System.Text;

using Npgsql;
using System.Text.Json;

var factory = new ConnectionFactory() { HostName = "rabbitmq" };

IConnection? connection = null;

while (connection == null)
{
    try
    {
        Console.WriteLine("Connecting to RabbitMQ...");
        connection = factory.CreateConnection();
    }
    catch
    {
        Console.WriteLine("RabbitMQ not ready, retrying in 5 seconds...");
        Thread.Sleep(5000);
    }
}

Console.WriteLine("Connected to RabbitMQ!");

using var channel = connection.CreateModel();

channel.QueueDeclare(
    queue: "task-queue",
    durable: false,
    exclusive: false,
    autoDelete: false);

Console.WriteLine("Waiting for messages...");

var consumer = new EventingBasicConsumer(channel);

consumer.Received += (model, ea) =>
{
    var body = ea.Body.ToArray();
    var message = Encoding.UTF8.GetString(body);

    Console.WriteLine($"Received message: {message}");

    var data = JsonSerializer.Deserialize<RequestMessage>(message);

    SaveToDatabase(data);

    Console.WriteLine("Saved to database");
};

channel.BasicConsume(
    queue: "task-queue",
    autoAck: true,
    consumer: consumer);

Console.WriteLine("Worker running...");

while (true)
{
    Thread.Sleep(1000);
}

void SaveToDatabase(RequestMessage data)
{
    // var connectionString =
    //     "Host=host.docker.internal;Username=postgres;Password=password;Database=postgres";

    var connectionString = Environment.GetEnvironmentVariable("DB_CONNECTION");

    using var conn = new NpgsqlConnection(connectionString);

    conn.Open();

    var cmd = new NpgsqlCommand(
        "INSERT INTO results(name,message) VALUES (@name,@message)", conn);

    cmd.Parameters.AddWithValue("name", data.Name);
    cmd.Parameters.AddWithValue("message", data.Message);

    cmd.ExecuteNonQuery();
}
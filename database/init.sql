CREATE TABLE results(
    id SERIAL PRIMARY KEY,
    name TEXT,
    message TEXT,
    processed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
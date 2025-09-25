USE employee_db;

CREATE TABLE IF NOT EXISTS employees (
  id UUID PRIMARY KEY,
  name text,
  role text,
  salary int
);

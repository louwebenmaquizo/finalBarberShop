# Barber API Documentation

> **Legacy reference only.** This PHP/MySQL API is disabled. The Flutter app
> now uses the Supabase schema and Edge Function in `../supabase/`.

## Base URL
- For browser/web: `http://localhost/barber_api/`
- For physical device: `http://192.168.1.7/barber_api/` (your computer's IP)
- For Android emulator: `http://10.0.2.2/barber_api/`

## Endpoints

### Authentication

#### POST /login.php
Login user
```json
{
  "username": "admin",
  "password": "password"
}
```
Response:
```json
{
  "success": true,
  "data": {
    "user_id": "...",
    "username": "admin",
    "email": "admin@example.com",
    "role": "admin",
    "is_active": true
  }
}
```

#### POST /register.php
Register new user
```json
{
  "full_name": "John Doe",
  "email": "john@example.com",
  "password": "password",
  "phone": "+84901234567"
}
```

### Customers

#### GET /customers.php
Get all customers

#### POST /customers.php
Create new customer

### Appointments

#### GET /appointments.php
Get all appointments

#### POST /appointments.php
Create new appointment

## Setup

1. Make sure XAMPP Apache is running
2. Access API at: `http://localhost/barber_api/login.php`
3. Test in browser first to verify it works


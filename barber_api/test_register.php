<?php
// Simple test script to verify register.php is working
// Access this file in browser: http://localhost/barber_api/test_register.php

header('Content-Type: text/html; charset=utf-8');

echo "<h1>Register.php Test</h1>";

// Check if config.php exists
if (!file_exists('config.php')) {
    echo "<p style='color: red;'>❌ config.php not found!</p>";
    echo "<p>Please create config.php with database credentials.</p>";
    exit();
}

echo "<p style='color: green;'>✅ config.php found</p>";

require_once 'config.php';

// Check database connection
try {
    $conn = new mysqli(DB_HOST, DB_USER, DB_PASS, DB_NAME);
    
    if ($conn->connect_error) {
        echo "<p style='color: red;'>❌ Database connection failed: " . $conn->connect_error . "</p>";
        exit();
    }
    
    echo "<p style='color: green;'>✅ Database connection successful</p>";
    
    // Check if users table exists
    $result = $conn->query("SHOW TABLES LIKE 'users'");
    if ($result && $result->num_rows > 0) {
        echo "<p style='color: green;'>✅ users table exists</p>";
    } else {
        echo "<p style='color: red;'>❌ users table not found!</p>";
    }
    
    // Check if customers table exists
    $result = $conn->query("SHOW TABLES LIKE 'customers'");
    if ($result && $result->num_rows > 0) {
        echo "<p style='color: green;'>✅ customers table exists</p>";
    } else {
        echo "<p style='color: red;'>❌ customers table not found!</p>";
    }
    
    // Check if customer role is allowed
    $result = $conn->query("SHOW CREATE TABLE users");
    if ($result) {
        $row = $result->fetch_assoc();
        $createTable = $row['Create Table'];
        if (strpos($createTable, "'customer'") !== false) {
            echo "<p style='color: green;'>✅ Customer role is allowed in users table</p>";
        } else {
            echo "<p style='color: orange;'>⚠️ Customer role might not be allowed. Check users table constraints.</p>";
        }
    }
    
    // Test register.php endpoint
    echo "<h2>Testing register.php endpoint</h2>";
    echo "<p>To test registration, use a tool like Postman or curl:</p>";
    echo "<pre>";
    echo "POST http://localhost/barber_api/register.php\n";
    echo "Content-Type: application/json\n\n";
    echo '{"full_name":"Test User","email":"test@example.com","phone":"+1234567890","password":"test123"}';
    echo "</pre>";
    
    $conn->close();
    
} catch (Exception $e) {
    echo "<p style='color: red;'>❌ Error: " . $e->getMessage() . "</p>";
}
?>


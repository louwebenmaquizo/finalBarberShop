<?php
require_once 'config.php';

header('Content-Type: application/json');

$conn = getDBConnection();

// Get all users
$result = $conn->query("SELECT user_id, username, email, role, is_active, password_hash FROM users");

$users = [];
while ($row = $result->fetch_assoc()) {
    // Don't expose full password hash, just show first few characters
    $row['password_hash'] = substr($row['password_hash'], 0, 10) . '...';
    $users[] = $row;
}

$conn->close();

echo json_encode([
    'success' => true,
    'count' => count($users),
    'users' => $users
], JSON_PRETTY_PRINT);
?>


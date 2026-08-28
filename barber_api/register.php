<?php
require_once 'config.php';

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    sendResponse(false, null, 'Invalid request method');
}

try {
    $input = json_decode(file_get_contents('php://input'), true);
    if (!$input) {
        sendResponse(false, null, 'Invalid JSON data');
    }

    $fullName = trim($input['full_name'] ?? '');
    $email = trim($input['email'] ?? '');
    $password = $input['password'] ?? '';
    $phone = trim($input['phone'] ?? '');
    $gender = !empty($input['gender']) ? trim($input['gender']) : null;
    $dateOfBirth = !empty($input['date_of_birth']) ? trim($input['date_of_birth']) : null;
    $rawProfilePicture = !empty($input['profile_picture']) ? $input['profile_picture'] : null;
    $notes = !empty($input['notes']) ? trim($input['notes']) : null;

    if (empty($fullName) || empty($email) || empty($password) || empty($phone)) {
        sendResponse(false, null, 'Full name, email, password, and phone are required');
    }

    if (strlen($password) < 6) {
        sendResponse(false, null, 'Password must be at least 6 characters');
    }

    $conn = getDBConnection();

    // Save profile picture as file in uploads/ if base64 provided
    $profilePicture = saveBase64Image($rawProfilePicture, 'cust');

    // Check if email already exists
    $stmt = $conn->prepare("SELECT user_id FROM users WHERE LOWER(TRIM(email)) = LOWER(?)");
    $stmt->bind_param("s", $email);
    $stmt->execute();
    if ($stmt->get_result()->num_rows > 0) {
        $stmt->close();
        $conn->close();
        sendResponse(false, null, 'Email already exists');
    }
    $stmt->close();

    // Check if phone already exists in customers table
    $stmt = $conn->prepare("SELECT customer_id FROM customers WHERE phone = ?");
    $stmt->bind_param("s", $phone);
    $stmt->execute();
    if ($stmt->get_result()->num_rows > 0) {
        $stmt->close();
        $conn->close();
        sendResponse(false, null, 'Phone number already registered');
    }
    $stmt->close();

    // Generate UUID for user_id
    $userId = sprintf(
        '%04x%04x-%04x-%04x-%04x-%04x%04x%04x',
        mt_rand(0, 0xffff), mt_rand(0, 0xffff),
        mt_rand(0, 0xffff),
        mt_rand(0, 0x0fff) | 0x4000,
        mt_rand(0, 0x3fff) | 0x8000,
        mt_rand(0, 0xffff), mt_rand(0, 0xffff), mt_rand(0, 0xffff)
    );

    // Derive username from email or phone
    $username = explode('@', $email)[0];
    // Ensure unique username
    $stmt = $conn->prepare("SELECT user_id FROM users WHERE username = ?");
    $stmt->bind_param("s", $username);
    $stmt->execute();
    if ($stmt->get_result()->num_rows > 0) {
        $username = $username . '_' . substr(md5(uniqid()), 0, 4);
    }
    $stmt->close();

    $role = 'customer';

    // Insert into users table
    $stmt = $conn->prepare("INSERT INTO users (user_id, username, email, password_hash, role, is_active) VALUES (?, ?, ?, ?, ?, 1)");
    $stmt->bind_param("sssss", $userId, $username, $email, $password, $role);
    if (!$stmt->execute()) {
        $error = $stmt->error;
        $stmt->close();
        $conn->close();
        sendResponse(false, null, 'Failed to create user: ' . $error);
    }
    $stmt->close();

    // Generate next customer_id (e.g. CUST001, CUST002)
    $result = $conn->query("SELECT customer_id FROM customers WHERE customer_id LIKE 'CUST%' ORDER BY customer_id DESC LIMIT 1");
    $customerId = 'CUST001';
    if ($result && $result->num_rows > 0) {
        $row = $result->fetch_assoc();
        $num = (int)substr($row['customer_id'], 4);
        $customerId = 'CUST' . str_pad($num + 1, 3, '0', STR_PAD_LEFT);
    }

    // Insert into customers table
    $stmt = $conn->prepare("INSERT INTO customers (customer_id, user_id, full_name, phone, email, gender, date_of_birth, profile_picture, notes) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)");
    $stmt->bind_param("sssssssss", $customerId, $userId, $fullName, $phone, $email, $gender, $dateOfBirth, $profilePicture, $notes);
    if (!$stmt->execute()) {
        $error = $stmt->error;
        $stmt->close();
        $conn->close();
        sendResponse(false, null, 'Failed to create customer profile: ' . $error);
    }
    $stmt->close();
    $conn->close();

    sendResponse(true, [
        'user_id' => $userId,
        'customer_id' => $customerId,
        'username' => $username,
        'full_name' => $fullName,
        'email' => $email,
        'phone' => $phone,
        'profile_picture' => $profilePicture,
        'role' => $role
    ]);
} catch (\Throwable $e) {
    sendResponse(false, null, 'Server error during registration: ' . $e->getMessage());
}
?>

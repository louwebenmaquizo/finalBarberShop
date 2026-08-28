<?php
require_once 'config.php';

if ($_SERVER['REQUEST_METHOD'] !== 'POST') sendResponse(false, null, 'Invalid request method');

$input = json_decode(file_get_contents('php://input'), true);
$username = $input['username'] ?? '';
$password = $input['password'] ?? '';

if (empty($username) || empty($password)) sendResponse(false, null, 'Username and password are required');

$conn = getDBConnection();
$stmt = $conn->prepare("SELECT user_id, username, email, role, is_active, password_hash FROM users WHERE (username = ? OR email = ?) AND is_active = TRUE");
$stmt->bind_param("ss", $username, $username);
$stmt->execute();
$result = $stmt->get_result();

if ($result->num_rows > 0) {
    $user = $result->fetch_assoc();
    if ($user['password_hash'] === $password) {
        unset($user['password_hash']);
        
        // If user is a barber or staff, fetch staff details
        if ($user['role'] === 'barber' || $user['role'] === 'staff') {
            $staffStmt = $conn->prepare("SELECT staff_id, name, phone, role as staff_role, skills, profile_photo FROM staff WHERE user_id = ? AND is_active = TRUE");
            $staffStmt->bind_param("s", $user['user_id']);
            $staffStmt->execute();
            $staffResult = $staffStmt->get_result();
            if ($staffResult && $staffResult->num_rows > 0) {
                $staff = $staffResult->fetch_assoc();
                $user['staff_id'] = $staff['staff_id'];
                $user['name'] = $staff['name'];
                $user['phone'] = $staff['phone'];
                $user['staff_role'] = $staff['staff_role'];
                $user['skills'] = $staff['skills'];
                $user['profile_photo'] = $staff['profile_photo'];
            }
            $staffStmt->close();
        } else if ($user['role'] === 'customer') {
            // If user is customer, fetch customer details
            $custStmt = $conn->prepare("SELECT customer_id, full_name, phone, profile_picture FROM customers WHERE user_id = ?");
            $custStmt->bind_param("s", $user['user_id']);
            $custStmt->execute();
            $custResult = $custStmt->get_result();
            if ($custResult && $custResult->num_rows > 0) {
                $cust = $custResult->fetch_assoc();
                $user['customer_id'] = $cust['customer_id'];
                $user['full_name'] = $cust['full_name'];
                $user['phone'] = $cust['phone'];
                $user['profile_picture'] = $cust['profile_picture'];
            }
            $custStmt->close();
        }
        
        sendResponse(true, $user);
    } else {
        sendResponse(false, null, 'Invalid password');
    }
} else {
    sendResponse(false, null, 'User not found or inactive');
}
$stmt->close();
$conn->close();
?>

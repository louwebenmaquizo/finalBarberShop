<?php
require_once 'config.php';

$conn = getDBConnection();
$method = $_SERVER['REQUEST_METHOD'];

switch ($method) {
    case 'GET':
        $customer_id = $_GET['customer_id'] ?? '';
        $user_id = $_GET['user_id'] ?? '';
        
        if (!empty($customer_id)) {
            $stmt = $conn->prepare("SELECT * FROM customers WHERE customer_id = ?");
            $stmt->bind_param("s", $customer_id);
            $stmt->execute();
            $result = $stmt->get_result();
            if ($result && $result->num_rows > 0) {
                sendResponse(true, $result->fetch_assoc());
            } else {
                sendResponse(false, null, 'Customer not found');
            }
            $stmt->close();
        } else if (!empty($user_id)) {
            $stmt = $conn->prepare("SELECT * FROM customers WHERE user_id = ?");
            $stmt->bind_param("s", $user_id);
            $stmt->execute();
            $result = $stmt->get_result();
            if ($result && $result->num_rows > 0) {
                sendResponse(true, $result->fetch_assoc());
            } else {
                sendResponse(false, null, 'Customer not found');
            }
            $stmt->close();
        } else {
            // Get all customers
            $result = $conn->query("SELECT * FROM customers ORDER BY created_at DESC");
            $customers = [];
            while ($row = $result->fetch_assoc()) {
                $customers[] = $row;
            }
            sendResponse(true, $customers);
        }
        break;
        
    case 'POST':
        // Create new customer
        $input = json_decode(file_get_contents('php://input'), true);
        $customer_id = 'CUST' . str_pad(rand(1, 99999), 5, '0', STR_PAD_LEFT);
        
        $profile_picture = null;
        if (!empty($input['profile_picture'])) {
            $profile_picture = saveBase64Image($input['profile_picture'], 'cust');
        }
        
        $stmt = $conn->prepare("INSERT INTO customers (customer_id, full_name, phone, email, profile_picture, registration_date) VALUES (?, ?, ?, ?, ?, CURRENT_DATE)");
        $stmt->bind_param("sssss", $customer_id, $input['full_name'], $input['phone'], $input['email'], $profile_picture);
        $stmt->execute();
        
        if ($stmt->affected_rows > 0) {
            sendResponse(true, ['customer_id' => $customer_id, 'profile_picture' => $profile_picture]);
        } else {
            sendResponse(false, null, 'Failed to create customer');
        }
        $stmt->close();
        break;
        
    case 'PUT':
        // Update customer profile
        $input = json_decode(file_get_contents('php://input'), true);
        $customer_id = $input['customer_id'] ?? '';
        $user_id = $input['user_id'] ?? '';
        
        if (empty($customer_id) && empty($user_id)) {
            sendResponse(false, null, 'Customer ID or User ID is required');
            break;
        }
        
        $updates = [];
        $params = [];
        $types = '';
        
        if (isset($input['full_name'])) {
            $updates[] = "full_name = ?";
            $params[] = trim($input['full_name']);
            $types .= 's';
        }
        if (isset($input['phone'])) {
            $updates[] = "phone = ?";
            $params[] = trim($input['phone']);
            $types .= 's';
        }
        if (isset($input['email'])) {
            $updates[] = "email = ?";
            $params[] = trim($input['email']);
            $types .= 's';
        }
        if (isset($input['gender'])) {
            $updates[] = "gender = ?";
            $params[] = trim($input['gender']);
            $types .= 's';
        }
        if (isset($input['date_of_birth'])) {
            $updates[] = "date_of_birth = ?";
            $params[] = trim($input['date_of_birth']);
            $types .= 's';
        }
        if (isset($input['notes'])) {
            $updates[] = "notes = ?";
            $params[] = trim($input['notes']);
            $types .= 's';
        }
        if (array_key_exists('profile_picture', $input)) {
            $raw_pic = $input['profile_picture'];
            $profile_picture = null;
            if (!empty($raw_pic)) {
                $profile_picture = saveBase64Image($raw_pic, 'cust');
            }
            $updates[] = "profile_picture = ?";
            $params[] = $profile_picture;
            $types .= 's';
        }
        
        if (empty($updates)) {
            sendResponse(false, null, 'No fields to update');
            break;
        }
        
        $whereClause = "";
        if (!empty($customer_id)) {
            $whereClause = "customer_id = ?";
            $params[] = $customer_id;
            $types .= 's';
        } else {
            $whereClause = "user_id = ?";
            $params[] = $user_id;
            $types .= 's';
        }
        
        $query = "UPDATE customers SET " . implode(', ', $updates) . " WHERE " . $whereClause;
        $stmt = $conn->prepare($query);
        $stmt->bind_param($types, ...$params);
        $stmt->execute();
        
        if ($stmt->affected_rows >= 0) {
            sendResponse(true, ['updated' => true, 'profile_picture' => $profile_picture ?? null]);
        } else {
            sendResponse(false, null, 'Failed to update customer profile: ' . $stmt->error);
        }
        $stmt->close();
        break;
}

$conn->close();
?>

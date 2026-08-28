<?php
// Start output buffering to catch any unexpected output
ob_start();

// Suppress error display and ensure clean JSON output
error_reporting(E_ALL);
ini_set('display_errors', 0);
ini_set('log_errors', 1);

require_once 'config.php';

// Clear any output that might have been generated
ob_clean();

try {
    $conn = getDBConnection();
    $method = $_SERVER['REQUEST_METHOD'];
} catch (Exception $e) {
    sendResponse(false, null, 'Database connection error: ' . $e->getMessage());
}

switch ($method) {
    case 'GET':
        // Check if requesting a specific employee by ID
        $staff_id = $_GET['staff_id'] ?? '';
        
        if (!empty($staff_id)) {
            // Get single employee by ID
            $stmt = $conn->prepare("SELECT 
                        s.staff_id, 
                        s.user_id, 
                        s.name, 
                        s.phone, 
                        s.email, 
                        s.role, 
                        s.skills, 
                        s.pay_rate, 
                        s.commission_rate, 
                        s.profile_photo, 
                        s.is_active,
                        s.created_at,
                        s.updated_at,
                        u.username
                      FROM staff s
                      LEFT JOIN users u ON s.user_id = u.user_id
                      WHERE s.staff_id = ?");
            $stmt->bind_param("s", $staff_id);
            $stmt->execute();
            $result = $stmt->get_result();
            
            if ($result && $result->num_rows > 0) {
                $employee = $result->fetch_assoc();
                sendResponse(true, $employee);
            } else {
                sendResponse(false, null, 'Employee not found');
            }
            $stmt->close();
        } else {
            // Get all employees/staff (including inactive)
            $include_inactive = $_GET['include_inactive'] ?? '0';
            
            $query = "SELECT 
                        s.staff_id, 
                        s.user_id, 
                        s.name, 
                        s.phone, 
                        s.email, 
                        s.role, 
                        s.skills, 
                        s.pay_rate, 
                        s.commission_rate, 
                        s.profile_photo, 
                        s.is_active,
                        s.created_at,
                        s.updated_at,
                        u.username
                      FROM staff s
                      LEFT JOIN users u ON s.user_id = u.user_id
                      WHERE s.role != 'admin'";
            
            if ($include_inactive != '1') {
                $query .= " AND s.is_active = TRUE";
            }
            
            $query .= " ORDER BY s.name ASC";
            
            $result = $conn->query($query);
            $employees = [];
            
            if ($result) {
                while ($row = $result->fetch_assoc()) {
                    $employees[] = $row;
                }
                sendResponse(true, $employees);
            } else {
                sendResponse(false, null, 'Error fetching employees: ' . $conn->error);
            }
        }
        break;
        
    case 'POST':
        // Create new employee & optional login user account
        try {
            $input = json_decode(file_get_contents('php://input'), true);
            
            if (json_last_error() !== JSON_ERROR_NONE) {
                sendResponse(false, null, 'Invalid JSON data: ' . json_last_error_msg());
                break;
            }
            
            // Validate required fields
            if (empty($input['name']) || empty($input['role'])) {
                sendResponse(false, null, 'Name and role are required');
                break;
            }

            $name = trim($input['name']);
            $phone = isset($input['phone']) && trim($input['phone']) !== '' ? trim($input['phone']) : null;
            $email = isset($input['email']) && trim($input['email']) !== '' ? trim($input['email']) : null;
            $skills = isset($input['skills']) && $input['skills'] !== '' ? $input['skills'] : null;
            $raw_photo = isset($input['profile_photo']) && $input['profile_photo'] !== '' ? $input['profile_photo'] : null;
            $profile_photo = saveBase64Image($raw_photo, 'barber');
            $pay_rate = isset($input['pay_rate']) && $input['pay_rate'] !== '' && $input['pay_rate'] !== null ? floatval($input['pay_rate']) : 0.0;
            $commission_rate = isset($input['commission_rate']) && $input['commission_rate'] !== '' && $input['commission_rate'] !== null ? floatval($input['commission_rate']) : 0.0;
            
            $user_id = isset($input['user_id']) && $input['user_id'] !== '' ? $input['user_id'] : null;
            $username = isset($input['username']) && $input['username'] !== '' ? trim($input['username']) : null;
            $password = isset($input['password']) && $input['password'] !== '' ? trim($input['password']) : null;

            // 1. Check for Duplicate Barber Name (case-insensitive)
            $nameCheck = $conn->prepare("SELECT staff_id FROM staff WHERE LOWER(TRIM(name)) = LOWER(?)");
            $nameCheck->bind_param("s", $name);
            $nameCheck->execute();
            if ($nameCheck->get_result()->num_rows > 0) {
                sendResponse(false, null, 'A barber or employee named "' . $name . '" already exists');
                $nameCheck->close();
                break;
            }
            $nameCheck->close();

            // 2. Check for Duplicate Phone (if provided)
            if (!empty($phone)) {
                $phoneCheck = $conn->prepare("SELECT staff_id FROM staff WHERE phone = ?");
                $phoneCheck->bind_param("s", $phone);
                $phoneCheck->execute();
                if ($phoneCheck->get_result()->num_rows > 0) {
                    sendResponse(false, null, 'Phone number "' . $phone . '" is already assigned to another barber');
                    $phoneCheck->close();
                    break;
                }
                $phoneCheck->close();
            }

            // 3. Check for Duplicate Email (if provided)
            if (!empty($email)) {
                $emailCheck = $conn->prepare("SELECT staff_id FROM staff WHERE LOWER(TRIM(email)) = LOWER(?)");
                $emailCheck->bind_param("s", $email);
                $emailCheck->execute();
                if ($emailCheck->get_result()->num_rows > 0) {
                    sendResponse(false, null, 'Email "' . $email . '" is already registered to another barber');
                    $emailCheck->close();
                    break;
                }
                $emailCheck->close();
            }
            
            $staff_id = 'ST' . str_pad(rand(1, 99999), 5, '0', STR_PAD_LEFT);
            
            // Handle is_active
            $is_active = true;
            if (isset($input['is_active'])) {
                if (is_bool($input['is_active'])) {
                    $is_active = $input['is_active'];
                } else if (is_int($input['is_active'])) {
                    $is_active = $input['is_active'] == 1;
                } else if (is_string($input['is_active'])) {
                    $is_active = $input['is_active'] == '1' || strtolower($input['is_active']) == 'true';
                }
            }
            $is_active_int = $is_active ? 1 : 0;
            
            // Create login user account if username and password are provided
            if (!empty($username) && !empty($password)) {
                // Check if username already exists in users table
                $checkStmt = $conn->prepare("SELECT user_id FROM users WHERE LOWER(TRIM(username)) = LOWER(?)");
                $checkStmt->bind_param("s", $username);
                $checkStmt->execute();
                $checkResult = $checkStmt->get_result();
                if ($checkResult && $checkResult->num_rows > 0) {
                    sendResponse(false, null, 'Username "' . $username . '" is already in use by another account');
                    $checkStmt->close();
                    break;
                }
                $checkStmt->close();
                
                // Create user in users table
                $new_user_id = sprintf(
                    '%04x%04x-%04x-%04x-%04x-%04x%04x%04x',
                    mt_rand(0, 0xffff), mt_rand(0, 0xffff),
                    mt_rand(0, 0xffff),
                    mt_rand(0, 0x0fff) | 0x4000,
                    mt_rand(0, 0x3fff) | 0x8000,
                    mt_rand(0, 0xffff), mt_rand(0, 0xffff), mt_rand(0, 0xffff)
                );
                
                $user_email = !empty($email) ? $email : ($username . '@liembarber.local');
                $user_role = 'barber';
                
                $userStmt = $conn->prepare("INSERT INTO users (user_id, username, email, password_hash, role, is_active) VALUES (?, ?, ?, ?, ?, 1)");
                $userStmt->bind_param("sssss", $new_user_id, $username, $user_email, $password, $user_role);
                if ($userStmt->execute()) {
                    $user_id = $new_user_id;
                }
                $userStmt->close();
            }
            
            // Insert into staff table
            $stmt = $conn->prepare("INSERT INTO staff (staff_id, user_id, name, phone, email, role, skills, pay_rate, commission_rate, profile_photo, is_active) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)");
            
            if (!$stmt) {
                sendResponse(false, null, 'Prepare failed: ' . $conn->error);
                break;
            }
            
            $stmt->bind_param("sssssssddsi", 
                $staff_id,
                $user_id,
                $name,
                $phone,
                $email,
                $input['role'],
                $skills,
                $pay_rate,
                $commission_rate,
                $profile_photo,
                $is_active_int
            );
            
            if (!$stmt->execute()) {
                sendResponse(false, null, 'Failed to create employee: ' . $stmt->error);
                $stmt->close();
                break;
            }
            
            if ($stmt->affected_rows > 0) {
                sendResponse(true, [
                    'staff_id' => $staff_id,
                    'user_id' => $user_id,
                    'username' => $username,
                    'has_account' => !empty($user_id)
                ]);
            } else {
                sendResponse(false, null, 'Failed to create employee: No rows affected');
            }
            $stmt->close();
        } catch (Exception $e) {
            sendResponse(false, null, 'Error creating employee: ' . $e->getMessage());
        }
        break;
        
    case 'PUT':
        // Update employee
        $input = json_decode(file_get_contents('php://input'), true);
        $staff_id = $input['staff_id'] ?? '';
        
        if (empty($staff_id)) {
            sendResponse(false, null, 'Staff ID is required');
            break;
        }

        // 1. Check for Duplicate Name if name is being updated
        if (!empty($input['name'])) {
            $name = trim($input['name']);
            $nameCheck = $conn->prepare("SELECT staff_id FROM staff WHERE LOWER(TRIM(name)) = LOWER(?) AND staff_id != ?");
            $nameCheck->bind_param("ss", $name, $staff_id);
            $nameCheck->execute();
            if ($nameCheck->get_result()->num_rows > 0) {
                sendResponse(false, null, 'Another barber named "' . $name . '" already exists');
                $nameCheck->close();
                break;
            }
            $nameCheck->close();
        }

        // 2. Check for Duplicate Phone if phone is being updated
        if (!empty($input['phone'])) {
            $phone = trim($input['phone']);
            $phoneCheck = $conn->prepare("SELECT staff_id FROM staff WHERE phone = ? AND staff_id != ?");
            $phoneCheck->bind_param("ss", $phone, $staff_id);
            $phoneCheck->execute();
            if ($phoneCheck->get_result()->num_rows > 0) {
                sendResponse(false, null, 'Phone number "' . $phone . '" is already assigned to another barber');
                $phoneCheck->close();
                break;
            }
            $phoneCheck->close();
        }

        // 3. Check for Duplicate Email if email is being updated
        if (!empty($input['email'])) {
            $email = trim($input['email']);
            $emailCheck = $conn->prepare("SELECT staff_id FROM staff WHERE LOWER(TRIM(email)) = LOWER(?) AND staff_id != ?");
            $emailCheck->bind_param("ss", $email, $staff_id);
            $emailCheck->execute();
            if ($emailCheck->get_result()->num_rows > 0) {
                sendResponse(false, null, 'Email "' . $email . '" is already registered to another barber');
                $emailCheck->close();
                break;
            }
            $emailCheck->close();
        }
        
        $updates = [];
        $params = [];
        $types = '';
        
        if (isset($input['profile_photo'])) {
            $input['profile_photo'] = saveBase64Image($input['profile_photo'], 'barber');
        }

        $fields = ['name', 'phone', 'email', 'role', 'skills', 'pay_rate', 'commission_rate', 'profile_photo', 'is_active'];
        foreach ($fields as $field) {
            if (isset($input[$field])) {
                $updates[] = "$field = ?";
                $params[] = $input[$field];
                $types .= $field === 'pay_rate' || $field === 'commission_rate' ? 'd' : ($field === 'is_active' ? 'i' : 's');
            }
        }
        
        if (empty($updates)) {
            sendResponse(false, null, 'No fields to update');
            break;
        }
        
        $params[] = $staff_id;
        $types .= 's';
        
        $query = "UPDATE staff SET " . implode(', ', $updates) . " WHERE staff_id = ?";
        $stmt = $conn->prepare($query);
        $stmt->bind_param($types, ...$params);
        $stmt->execute();
        
        if ($stmt->affected_rows >= 0) {
            sendResponse(true, ['staff_id' => $staff_id, 'updated' => true]);
        } else {
            sendResponse(false, null, 'Failed to update employee: ' . $stmt->error);
        }
        $stmt->close();
        break;
        
    case 'DELETE':
        // Soft delete employee (set is_active to FALSE)
        $input = json_decode(file_get_contents('php://input'), true);
        $staff_id = $input['staff_id'] ?? $_GET['staff_id'] ?? '';
        
        if (empty($staff_id)) {
            sendResponse(false, null, 'Staff ID is required');
            break;
        }
        
        $stmt = $conn->prepare("UPDATE staff SET is_active = FALSE WHERE staff_id = ?");
        $stmt->bind_param("s", $staff_id);
        $stmt->execute();
        
        if ($stmt->affected_rows > 0) {
            sendResponse(true, ['staff_id' => $staff_id, 'deleted' => true]);
        } else {
            sendResponse(false, null, 'Failed to delete employee: ' . $stmt->error);
        }
        $stmt->close();
        break;
        
    default:
        sendResponse(false, null, 'Method not allowed');
}

$conn->close();
?>
